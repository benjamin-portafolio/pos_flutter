import 'dart:convert';

import 'package:http/http.dart' as http;

import '../commands/local_command_context.dart';
import '../../data/local/drift/app_database.dart';
import 'models/sync_event.dart';
import 'sync_endpoint_config.dart';

class SyncPushService {
  SyncPushService({
    required EventDao eventDao,
    required SyncEndpointConfig endpointConfig,
    required LocalCommandContext commandContext,
    http.Client? client,
  }) : _eventDao = eventDao,
       _endpointConfig = endpointConfig,
       _commandContext = commandContext,
       _client = client ?? http.Client();

  final EventDao _eventDao;
  final SyncEndpointConfig _endpointConfig;
  final LocalCommandContext _commandContext;
  final http.Client _client;

  Future<SyncPushReport> pushEvent(SyncEvent event) {
    return _pushEvents([event]);
  }

  Future<SyncPushReport> pushPendingEvents() async {
    final records = await _eventDao.obtenerEventosPendientes();
    final events = records.map(_eventFromRecord).toList();
    return _pushEvents(events);
  }

  Future<SyncConnectionCheck> testConnection() async {
    final response = await _postPushBody(
      deviceId: _commandContext.deviceId,
      events: const [],
      requireSuccessfulStatus: false,
    );

    return SyncConnectionCheck(
      statusCode: response.statusCode,
      body: response.body,
    );
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
        case 'duplicate':
          await _eventDao.actualizarEstadoSincronizacion(
            event.eventId,
            'synced',
            serverSequence: result?.serverSequence,
            serverTime: result?.serverTime,
          );
          synced++;
          break;
        case 'rejected':
          await _eventDao.actualizarEstadoSincronizacion(
            event.eventId,
            'rejected',
            serverSequence: result?.serverSequence,
            serverTime: result?.serverTime,
          );
          rejected++;
          break;
        case 'conflict':
          await _eventDao.actualizarEstadoSincronizacion(
            event.eventId,
            'conflict',
            serverSequence: result?.serverSequence,
            serverTime: result?.serverTime,
          );
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
    bool requireSuccessfulStatus = true,
  }) async {
    final uri = Uri.parse('${_endpointConfig.baseUrl}/sync/push');
    final body = <String, Object?>{
      'device_id': deviceId,
      'last_full_pull_server_sequence': null,
      'last_preflight_server_sequence': null,
      'events': events,
    };

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (requireSuccessfulStatus &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
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

  SyncEvent _eventFromRecord(EventRecord record) {
    return SyncEvent(
      eventId: record.eventId,
      aggregateType: record.aggregateType,
      aggregateId: record.aggregateId,
      eventType: record.eventType,
      deviceId: record.deviceId,
      userId: record.userId,
      localSequence: record.localSequence,
      serverSequence: record.serverSequence,
      baseServerSequence: record.baseServerSequence,
      baseVersion: record.baseVersion,
      createdAtLocal: record.createdAtLocal,
      createdAtServer: record.createdAtServer,
      payload: _decodePayload(record.payload),
      syncStatus: record.syncStatus,
    );
  }

  Map<String, Object?> _decodePayload(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
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

class SyncPushReport {
  const SyncPushReport({
    required this.total,
    required this.synced,
    required this.rejected,
    required this.conflicts,
    required this.pending,
  });

  const SyncPushReport.empty()
    : total = 0,
      synced = 0,
      rejected = 0,
      conflicts = 0,
      pending = 0;

  final int total;
  final int synced;
  final int rejected;
  final int conflicts;
  final int pending;
}

class SyncConnectionCheck {
  const SyncConnectionCheck({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}

class SyncPushException implements Exception {
  const SyncPushException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _RemoteEventResult {
  const _RemoteEventResult({
    required this.status,
    required this.serverSequence,
    required this.serverTime,
  });

  final String status;
  final int? serverSequence;
  final DateTime? serverTime;
}
