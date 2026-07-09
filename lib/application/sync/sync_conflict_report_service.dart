import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exceptions/sync_conflict_report_exception.dart';
import 'models/sync_event.dart';
import 'models/sync_push_report.dart';
import 'sync_conflict_projection_cleaner.dart';
import 'sync_endpoint_config.dart';
import 'sync_persistence.dart';

class SyncConflictReportService {
  SyncConflictReportService({
    required SyncPersistence syncPersistence,
    required SyncEndpointConfig endpointConfig,
    required SyncConflictProjectionCleaner conflictProjectionCleaner,
    http.Client? client,
  }) : _syncPersistence = syncPersistence,
       _endpointConfig = endpointConfig,
       _conflictProjectionCleaner = conflictProjectionCleaner,
       _client = client ?? http.Client();

  final SyncPersistence _syncPersistence;
  final SyncEndpointConfig _endpointConfig;
  final SyncConflictProjectionCleaner _conflictProjectionCleaner;
  final http.Client _client;

  Future<SyncPushReport> reportLocalConflicts() async {
    final events = await _syncPersistence.unreportedConflictEvents();
    if (events.isEmpty) return const SyncPushReport.empty();

    final refs = await _syncPersistence.refsForEvents(
      events.map((event) => event.eventId).toList(),
    );
    final response = await _postConflictReport(events, refs);
    final results = _extractRemoteResults(_decodeResponseBody(response.body));

    var conflicts = 0;
    var rejected = 0;
    var pending = 0;

    for (final event in events) {
      final result = results[event.eventId];
      final effectiveStatus = result?.effectiveStatus ?? 'pending';

      if (effectiveStatus == 'conflict') {
        await _syncPersistence.updateEventSyncStatus(
          event.eventId,
          'conflict',
          serverSequence: result?.serverSequence,
          serverTime: result?.serverTime,
          rejectionReason: result?.reason,
        );
        final serverSequence = result?.serverSequence;
        if (serverSequence != null) {
          await _syncPersistence.markRefsSynced(event.eventId, serverSequence);
        }
        await _conflictProjectionCleaner.hideConflictProjection(event);
        conflicts++;
      } else if (effectiveStatus == 'rejected') {
        await _syncPersistence.updateEventSyncStatus(
          event.eventId,
          'rejected',
          serverSequence: result?.serverSequence,
          serverTime: result?.serverTime,
          rejectionReason: result?.reason,
        );
        rejected++;
      } else {
        pending++;
      }
    }

    return SyncPushReport(
      total: events.length,
      synced: 0,
      rejected: rejected,
      conflicts: conflicts,
      pending: pending,
    );
  }

  Future<http.Response> _postConflictReport(
    List<SyncEvent> events,
    List<StoredEventRef> refs,
  ) async {
    final uri = Uri.parse('${_endpointConfig.baseUrl}/sync/conflicts/report');
    final refsByEventId = _refsByEventId(refs);
    final body = <String, Object?>{
      'device_id': events.first.deviceId,
      'events': events
          .map(
            (event) => _conflictEventJson(event, refsByEventId[event.eventId]),
          )
          .toList(),
    };

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncConflictReportException(
          'Error reportando conflictos: ${response.statusCode} ${response.body}',
        );
      }

      return response;
    } on SyncConflictReportException {
      rethrow;
    } catch (error) {
      throw SyncConflictReportException('Error reportando conflictos: $error');
    }
  }

  Map<String, List<StoredEventRef>> _refsByEventId(List<StoredEventRef> refs) {
    final grouped = <String, List<StoredEventRef>>{};
    for (final ref in refs) {
      grouped.putIfAbsent(ref.eventId, () => <StoredEventRef>[]).add(ref);
    }
    return grouped;
  }

  Map<String, Object?> _conflictEventJson(
    SyncEvent event,
    List<StoredEventRef>? refs,
  ) {
    return {
      ...event.toPushJson(),
      'reason':
          event.rejectionReason ??
          'Conflicto detectado localmente por el dispositivo.',
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

  Map<String, Object?> _decodeResponseBody(String body) {
    if (body.trim().isEmpty) return const <String, Object?>{};

    final decoded = jsonDecode(body);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }

    throw const SyncConflictReportException('Respuesta invalida del servidor.');
  }

  Map<String, _RemoteConflictResult> _extractRemoteResults(
    Map<String, Object?> responseBody,
  ) {
    final results = <String, _RemoteConflictResult>{};
    final resultLists = [
      responseBody['events'],
      responseBody['results'],
      responseBody['event_results'],
    ];

    for (final resultList in resultLists) {
      if (resultList is! List) continue;

      for (final item in resultList) {
        if (item is! Map) continue;
        final data = item.cast<String, Object?>();
        final eventId = data['event_id'] as String?;
        final status = _readStatus(data);
        if (eventId == null || status == null) continue;

        results[eventId] = _RemoteConflictResult(
          status: status,
          serverSequence: _readInt(data['server_sequence']),
          serverTime: _readDateTime(
            data['created_at_server'] ?? data['server_time'],
          ),
          originalSyncStatus: _readOriginalSyncStatus(data),
          reason: data['reason'] as String?,
        );
      }
    }

    return results;
  }

  String? _readStatus(Map<String, Object?> data) {
    final value = data['status'] ?? data['result'] ?? data['state'];
    if (value is! String) return null;

    final normalized = value.toLowerCase();
    const knownStatuses = {'reported', 'duplicate', 'rejected', 'conflict'};
    return knownStatuses.contains(normalized) ? normalized : null;
  }

  String? _readOriginalSyncStatus(Map<String, Object?> data) {
    final value = data['original_sync_status'] ?? data['sync_status'];
    if (value is! String) return null;

    final normalized = value.toLowerCase();
    const knownStatuses = {
      'pending',
      'synced',
      'delivered',
      'rejected',
      'conflict',
    };
    if (!knownStatuses.contains(normalized)) return null;
    return normalized == 'synced' ? 'delivered' : normalized;
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  DateTime? _readDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}

class _RemoteConflictResult {
  const _RemoteConflictResult({
    required this.status,
    required this.serverSequence,
    required this.serverTime,
    required this.originalSyncStatus,
    required this.reason,
  });

  final String status;
  final int? serverSequence;
  final DateTime? serverTime;
  final String? originalSyncStatus;
  final String? reason;

  String get effectiveStatus {
    if (status == 'duplicate') {
      return originalSyncStatus ?? 'conflict';
    }
    if (status == 'reported') return 'conflict';
    return status;
  }
}
