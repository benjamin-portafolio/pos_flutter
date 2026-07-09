import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exceptions/sync_push_exception.dart';
import 'models/sync_event.dart';
import 'models/sync_push_report.dart';
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
    return _pushEvents(events);
  }

  Future<SyncPushReport> _pushEvents(List<SyncEvent> events) async {
    if (events.isEmpty) return const SyncPushReport.empty();

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

    var synced = 0;
    var rejected = 0;
    var conflicts = 0;
    var pending = 0;

    for (final event in events) {
      final result = remoteResults[event.eventId];
      switch (result?.status) {
        case 'accepted':
          await _syncPersistence.updateEventSyncStatus(
            event.eventId,
            'delivered',
            serverSequence: result?.serverSequence,
            serverTime: result?.serverTime,
            rejectionReason: result?.reason,
          );
          final serverSequence = result?.serverSequence;
          if (serverSequence != null) {
            await _syncPersistence.markRefsSynced(
              event.eventId,
              serverSequence,
            );
          }
          synced++;
          break;
        case 'duplicate':
          final effectiveStatus = result?.originalSyncStatus ?? 'delivered';
          if (effectiveStatus == 'delivered') {
            await _syncPersistence.updateEventSyncStatus(
              event.eventId,
              'delivered',
              serverSequence: result?.serverSequence,
              serverTime: result?.serverTime,
              rejectionReason: result?.reason,
            );
            final serverSequence = result?.serverSequence;
            if (serverSequence != null) {
              await _syncPersistence.markRefsSynced(
                event.eventId,
                serverSequence,
              );
            }
            synced++;
          } else if (effectiveStatus == 'conflict') {
            await _syncPersistence.updateEventSyncStatus(
              event.eventId,
              'conflict',
              serverSequence: result?.serverSequence,
              serverTime: result?.serverTime,
              rejectionReason: result?.reason,
            );
            final serverSequence = result?.serverSequence;
            if (serverSequence != null) {
              await _syncPersistence.markRefsSynced(
                event.eventId,
                serverSequence,
              );
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
            final serverSequence = result?.serverSequence;
            if (serverSequence != null) {
              await _syncPersistence.markRefsSynced(
                event.eventId,
                serverSequence,
              );
            }
            rejected++;
          } else {
            pending++;
          }
          break;
        case 'rejected':
          await _syncPersistence.updateEventSyncStatus(
            event.eventId,
            'rejected',
            serverSequence: result?.serverSequence,
            serverTime: result?.serverTime,
            rejectionReason: result?.reason,
          );
          final serverSequence = result?.serverSequence;
          if (serverSequence != null) {
            await _syncPersistence.markRefsSynced(
              event.eventId,
              serverSequence,
            );
          }
          rejected++;
          break;
        case 'conflict':
          await _syncPersistence.updateEventSyncStatus(
            event.eventId,
            'conflict',
            serverSequence: result?.serverSequence,
            serverTime: result?.serverTime,
            rejectionReason: result?.reason,
          );
          final serverSequence = result?.serverSequence;
          if (serverSequence != null) {
            await _syncPersistence.markRefsSynced(
              event.eventId,
              serverSequence,
            );
          }
          await _conflictProjectionCleaner.hideConflictProjection(event);
          conflicts++;
          break;
        default:
          pending++;
          break;
      }
    }

    return SyncPushReport(
      total: events.length,
      synced: synced,
      rejected: rejected,
      conflicts: conflicts,
      pending: pending,
    );
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
