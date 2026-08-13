import 'dart:convert';

import 'package:http/http.dart' as http;

import '../commands/local_command_context.dart';
import 'exceptions/sync_preflight_exception.dart';
import 'models/pending_revalidation_report.dart';
import 'models/sync_event.dart';
import 'models/sync_preflight_report.dart';
import 'pending_event_revalidator.dart';
import 'payloads/categoria_movida_payload.dart';
import 'payloads/categoria_eliminada_payload.dart';
import 'remote_event_applier.dart';
import 'sync_endpoint_config.dart';
import 'sync_persistence.dart';

class SyncPreflightService {
  SyncPreflightService({
    required SyncPersistence syncPersistence,
    required SyncEndpointConfig endpointConfig,
    required LocalCommandContext commandContext,
    required RemoteEventApplier remoteEventApplier,
    required PendingEventRevalidator pendingEventRevalidator,
    http.Client? client,
  }) : _syncPersistence = syncPersistence,
       _endpointConfig = endpointConfig,
       _commandContext = commandContext,
       _remoteEventApplier = remoteEventApplier,
       _pendingEventRevalidator = pendingEventRevalidator,
       _client = client ?? http.Client();

  static const defaultMaxEvents = 500;

  final SyncPersistence _syncPersistence;
  final SyncEndpointConfig _endpointConfig;
  final LocalCommandContext _commandContext;
  final RemoteEventApplier _remoteEventApplier;
  final PendingEventRevalidator _pendingEventRevalidator;
  final http.Client _client;

  Future<SyncPreflightReport> preflightPendingEvents({
    int maxEvents = defaultMaxEvents,
    int? latestServerSequence,
  }) async {
    final pendingEvents = await _syncPersistence.pendingEvents();
    if (pendingEvents.isEmpty) {
      return const SyncPreflightReport.skipped(reason: 'no_pending_events');
    }

    if (latestServerSequence != null) {
      final lastFullPullServerSequence = await _syncPersistence
          .lastFullPullServerSequence();
      if (lastFullPullServerSequence >= latestServerSequence) {
        final revalidation = await _pendingEventRevalidator
            .revalidatePendingEvents();
        return SyncPreflightReport.skipped(
          pendingCount: pendingEvents.length,
          reason: 'server_sequence_current',
          localConflicts: revalidation.conflicts,
        );
      }
    }

    final refs = await _syncPersistence.refsForEvents(
      pendingEvents.map((event) => event.eventId).toList(),
    );

    if (!_requiresPreflight(pendingEvents, refs)) {
      return SyncPreflightReport.skipped(
        pendingCount: pendingEvents.length,
        reason: 'not_required',
      );
    }

    final response = await _postPreflight(
      pendingEvents: pendingEvents,
      refs: refs,
      maxEvents: maxEvents,
    );

    late PendingRevalidationReport revalidation;
    await _remoteEventApplier.applySyncedEvents(
      response.events,
      afterApply: () async {
        await _syncPersistence.updateLastPreflightServerSequence(
          response.preflightSequence,
        );
        revalidation = await _pendingEventRevalidator.revalidatePendingEvents();
      },
    );

    return SyncPreflightReport(
      skipped: false,
      pendingCount: pendingEvents.length,
      impactingEvents: response.events.length,
      preflightSequence: response.preflightSequence,
      hasMore: response.hasMore,
      requiresFullPullBeforePush: response.requiresFullPullBeforePush,
      reason: response.reason,
      localConflicts: revalidation.conflicts,
    );
  }

  Future<PendingRevalidationReport> revalidatePendingEvents() {
    return _pendingEventRevalidator.revalidatePendingEvents();
  }

  Future<_PreflightResponse> _postPreflight({
    required List<SyncEvent> pendingEvents,
    required List<StoredEventRef> refs,
    required int maxEvents,
  }) async {
    final uri = Uri.parse('${_endpointConfig.baseUrl}/sync/preflight');
    final lastFullPullServerSequence = await _syncPersistence
        .lastFullPullServerSequence();
    final refsByEventId = _refsByEventId(refs);

    final body = <String, Object?>{
      'device_id': _commandContext.deviceId,
      'last_full_pull_server_sequence': lastFullPullServerSequence,
      'max_events': maxEvents,
      'pending_refs': pendingEvents
          .map((event) => _pendingRefJson(event, refsByEventId[event.eventId]))
          .toList(),
    };

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncPreflightException(
          'Error en preflight: ${response.statusCode} ${response.body}',
        );
      }

      return _decodePreflightResponse(response.body);
    } on SyncPreflightException {
      rethrow;
    } catch (error) {
      throw SyncPreflightException('Error en preflight: $error');
    }
  }

  Map<String, List<StoredEventRef>> _refsByEventId(List<StoredEventRef> refs) {
    final grouped = <String, List<StoredEventRef>>{};
    for (final ref in refs) {
      grouped.putIfAbsent(ref.eventId, () => <StoredEventRef>[]).add(ref);
    }
    return grouped;
  }

  Map<String, Object?> _pendingRefJson(
    SyncEvent event,
    List<StoredEventRef>? refs,
  ) {
    return {
      'event_id': event.eventId,
      'event_type': event.eventType,
      'aggregate_type': event.aggregateType,
      'aggregate_id': event.aggregateId,
      'base_server_sequence': event.baseServerSequence,
      'base_version': event.baseVersion,
      'changed_fields': _readChangedFields(event.payload),
      'refs': (refs ?? const <StoredEventRef>[])
          .map(
            (ref) => {
              'type': ref.refType,
              'id': ref.refId,
              'relationship': ref.relationship,
            },
          )
          .toList(),
    };
  }

  bool _requiresPreflight(List<SyncEvent> events, List<StoredEventRef> refs) {
    if (refs.any((ref) => ref.relationship != 'affects')) return true;

    for (final event in events) {
      if (event.eventType == CategoriaMovidaPayload.eventType) return true;
      if (event.eventType == CategoriaEliminadaPayload.eventType) return true;
      if (event.eventType.endsWith('_actualizado')) return true;
      if (_readChangedFields(event.payload).isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  _PreflightResponse _decodePreflightResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const SyncPreflightException('Respuesta preflight invalida.');
    }

    final data = decoded.cast<String, Object?>();
    final rawEvents = data['events'];
    if (rawEvents is! List) {
      throw const SyncPreflightException(
        'Respuesta preflight sin arreglo events.',
      );
    }

    final events = rawEvents
        .whereType<Map>()
        .map((event) => SyncEvent.fromJson(event.cast<String, Object?>()))
        .toList();

    return _PreflightResponse(
      events: events,
      preflightSequence: _readRequiredInt(
        data['preflight_sequence'],
        'preflight_sequence',
      ),
      hasMore: data['has_more'] == true,
      requiresFullPullBeforePush:
          data['requires_full_pull_before_push'] == true,
      reason: data['reason'] as String?,
    );
  }

  List<String> _readChangedFields(Map<String, Object?> payload) {
    final value = payload['changed_fields'];
    if (value is! List) return const <String>[];

    return value.whereType<String>().toList(growable: false);
  }

  int _readRequiredInt(Object? value, String fieldName) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }

    throw SyncPreflightException('Respuesta preflight sin $fieldName valido.');
  }
}

class _PreflightResponse {
  const _PreflightResponse({
    required this.events,
    required this.preflightSequence,
    required this.hasMore,
    required this.requiresFullPullBeforePush,
    required this.reason,
  });

  final List<SyncEvent> events;
  final int preflightSequence;
  final bool hasMore;
  final bool requiresFullPullBeforePush;
  final String? reason;
}
