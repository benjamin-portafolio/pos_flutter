import 'payloads/cliente_actualizado_payload.dart';
import 'payloads/abono_cliente_registrado_payload.dart';
import 'payloads/venta_confirmada_payload.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exceptions/sync_push_exception.dart';
import 'models/sync_event.dart';
import 'models/sync_push_report.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_eliminada_payload.dart';
import 'payloads/categoria_movida_payload.dart';
import 'payloads/producto_creado_payload.dart';
import 'payloads/producto_actualizado_payload.dart';
import 'payloads/movimiento_inventario_registrado_payload.dart';
import 'payloads/recurso_inventario_actualizado_payload.dart';
import 'sync_conflict_projection_cleaner.dart';
import 'sync_endpoint_config.dart';
import 'sync_persistence.dart';

class SyncPushService {
  SyncPushService({
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

  Future<SyncPushReport> pushPendingEvents() async {
    final events = await _syncPersistence.pendingEvents();
    final pendingEventIds = events.map((event) => event.eventId).toSet();
    final eligibleEvents = <SyncEvent>[];
    final waitingEvents = <SyncEvent>[];
    for (final event in events) {
      final target = _dependsOnEventIds(event, pendingEventIds)
          ? waitingEvents
          : eligibleEvents;
      target.add(event);
    }
    return _pushEvents(eligibleEvents, waitingEvents: waitingEvents);
  }

  Future<SyncPushReport> _pushEvents(
    List<SyncEvent> events, {
    List<SyncEvent> waitingEvents = const [],
  }) async {
    if (events.isEmpty) {
      return SyncPushReport(
        total: waitingEvents.length,
        synced: 0,
        rejected: 0,
        conflicts: 0,
        pending: waitingEvents.length,
      );
    }

    final response = await _postEvents(events);
    final Map<String, Object?> decodedBody;
    final Map<String, _RemoteEventResult> remoteResults;
    try {
      decodedBody = _decodeResponseBody(response.body);
      remoteResults = _extractRemoteResults(decodedBody, events);
    } on SyncPushException {
      rethrow;
    } catch (error) {
      throw SyncPushException('Respuesta invalida del servidor: $error');
    }

    return _syncPersistence.runInTransaction(
      () => _applyPushResults(events, waitingEvents, remoteResults),
    );
  }

  Future<SyncPushReport> _applyPushResults(
    List<SyncEvent> events,
    List<SyncEvent> waitingEvents,
    Map<String, _RemoteEventResult> remoteResults,
  ) async {
    var synced = 0;
    var rejected = 0;
    var pending = 0;
    final conflictEvents = <SyncEvent>[];

    for (final event in events) {
      final result = remoteResults[event.eventId];
      final status = _effectiveDeliveryStatus(result);
      if (status == 'pending') {
        pending++;
        continue;
      }
      await _persistRemoteResult(event, result!, status);
      switch (status) {
        case 'delivered':
          synced++;
        case 'rejected':
          rejected++;
        case 'conflict':
          conflictEvents.add(event);
      }
    }

    final waitingConflicts = await _propagateWaitingConflicts(
      waitingEvents,
      conflictEvents,
    );
    for (final event in conflictEvents.reversed) {
      await _conflictProjectionCleaner.hideConflictProjection(event);
    }

    return SyncPushReport(
      total: events.length + waitingEvents.length,
      synced: synced,
      rejected: rejected,
      conflicts: conflictEvents.length,
      pending: pending + waitingEvents.length - waitingConflicts,
    );
  }

  String _effectiveDeliveryStatus(_RemoteEventResult? result) {
    return switch (result?.status) {
      'accepted' => 'delivered',
      'duplicate' => result!.originalSyncStatus ?? 'delivered',
      'rejected' => 'rejected',
      'conflict' => 'conflict',
      _ => 'pending',
    };
  }

  Future<void> _persistRemoteResult(
    SyncEvent event,
    _RemoteEventResult result,
    String status,
  ) async {
    await _syncPersistence.updateEventSyncStatus(
      event.eventId,
      status,
      serverSequence: result.serverSequence,
      serverTime: result.serverTime,
      rejectionReason: result.reason,
    );
    final serverSequence = result.serverSequence;
    if (serverSequence != null) {
      await _syncPersistence.markRefsSynced(event.eventId, serverSequence);
    }
  }

  Future<int> _propagateWaitingConflicts(
    List<SyncEvent> waitingEvents,
    List<SyncEvent> conflictEvents,
  ) async {
    final conflictedEventIds = conflictEvents
        .map((event) => event.eventId)
        .toSet();
    var waitingConflicts = 0;
    for (final event in waitingEvents) {
      if (!_dependsOnEventIds(event, conflictedEventIds)) continue;

      await _syncPersistence.updateEventSyncStatus(
        event.eventId,
        'conflict',
        rejectionReason: 'El evento depende de otro evento local en conflicto.',
      );
      conflictEvents.add(event);
      conflictedEventIds.add(event.eventId);
      waitingConflicts++;
    }
    return waitingConflicts;
  }

  bool _dependsOnEventIds(SyncEvent event, Set<String> eventIds) {
    switch (event.eventType) {
      case ClienteActualizadoPayload.eventType:
        return eventIds.contains(
          ClienteActualizadoPayload.fromJson(event.payload).baseEventId,
        );
      case AbonoClienteRegistradoPayload.eventType:
        return AbonoClienteRegistradoPayload.fromJson(
          event.payload,
        ).dependencyEventIds.any(eventIds.contains);
      case VentaConfirmadaPayload.eventType:
        return VentaConfirmadaPayload.fromJson(
          event.payload,
        ).dependencyEventIds.any(eventIds.contains);
      case CategoriaActualizadaPayload.eventType:
        final payload = CategoriaActualizadaPayload.fromJson(event.payload);
        return eventIds.contains(payload.baseEventId);
      case CategoriaMovidaPayload.eventType:
        final payload = CategoriaMovidaPayload.fromJson(event.payload);
        return eventIds.contains(payload.baseEventId) ||
            eventIds.contains(payload.categoriaDesplazadaBaseEventId);
      case CategoriaEliminadaPayload.eventType:
        final payload = CategoriaEliminadaPayload.fromJson(event.payload);
        return eventIds.contains(payload.baseEventId) ||
            payload.categoriasDesplazadas.any(
              (category) => eventIds.contains(category.baseEventId),
            );
      case ProductoActualizadoPayload.eventType:
        return ProductoActualizadoPayload.fromJson(
          event.payload,
        ).dependencyEventIds.any(eventIds.contains);
      case ProductoCreadoPayload.eventType:
        final payload = ProductoCreadoPayload.fromJson(event.payload);
        return switch (payload.dependenciaCategoria?.dependsOnEventId) {
              final dependencyEventId? => eventIds.contains(dependencyEventId),
              null => false,
            } ||
            payload.dependenciasInventario.any(
              (dependency) =>
                  dependency.dependsOnEventId != null &&
                  eventIds.contains(dependency.dependsOnEventId),
            );
      case RecursoInventarioActualizadoPayload.eventType:
        final payload = RecursoInventarioActualizadoPayload.fromJson(
          event.payload,
        );
        return eventIds.contains(payload.baseEventId);
      case MovimientoInventarioRegistradoPayload.eventType:
        final payload = MovimientoInventarioRegistradoPayload.fromJson(
          event.payload,
        );
        return eventIds.contains(payload.baseEventId);
      default:
        return false;
    }
  }

  Future<http.Response> _postEvents(List<SyncEvent> events) async {
    return _postPushBody(
      deviceId: events.first.deviceId,
      events: events.map((event) => event.toPushJson()).toList(),
    );
  }

  Future<http.Response> _postPushBody({
    required String deviceId,
    required List<Map<String, Object?>> events,
  }) async {
    final uri = Uri.parse('${_endpointConfig.baseUrl}/sync/push');
    final lastFullPullServerSequence = await _syncPersistence
        .lastFullPullServerSequence();
    final lastPreflightServerSequence = await _syncPersistence
        .lastPreflightServerSequence();
    final body = <String, Object?>{
      'device_id': deviceId,
      'last_full_pull_server_sequence': lastFullPullServerSequence,
      'last_preflight_server_sequence': lastPreflightServerSequence == 0
          ? null
          : lastPreflightServerSequence,
      'events': events,
    };

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncPushException(
          'Error enviando eventos: ${response.statusCode} ${response.body}',
        );
      }

      return response;
    } on SyncPushException {
      rethrow;
    } catch (error) {
      throw SyncPushException('Error enviando eventos: $error');
    }
  }

  Map<String, Object?> _decodeResponseBody(String body) {
    if (body.trim().isEmpty) return const <String, Object?>{};

    final decoded = jsonDecode(body);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }

    throw const SyncPushException('Respuesta invalida del servidor.');
  }

  Map<String, _RemoteEventResult> _extractRemoteResults(
    Map<String, Object?> responseBody,
    List<SyncEvent> events,
  ) {
    final results = <String, _RemoteEventResult>{};
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

        results[eventId] = _RemoteEventResult(
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

    final topLevelStatus = _readStatus(responseBody);
    if (topLevelStatus != null && results.isEmpty) {
      for (final event in events) {
        results[event.eventId] = _RemoteEventResult(
          status: topLevelStatus,
          serverSequence: _readInt(responseBody['server_sequence']),
          serverTime: _readDateTime(
            responseBody['created_at_server'] ?? responseBody['server_time'],
          ),
          originalSyncStatus: _readOriginalSyncStatus(responseBody),
          reason: responseBody['reason'] as String?,
        );
      }
    }

    return results;
  }

  String? _readStatus(Map<String, Object?> data) {
    final value = data['status'] ?? data['result'] ?? data['state'];
    if (value is! String) return null;

    final normalized = value.toLowerCase();
    const knownStatuses = {'accepted', 'duplicate', 'rejected', 'conflict'};
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

class _RemoteEventResult {
  const _RemoteEventResult({
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
}
