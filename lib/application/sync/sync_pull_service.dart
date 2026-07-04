import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/local/drift/app_database.dart';
import '../commands/local_command_context.dart';
import 'exceptions/sync_pull_exception.dart';
import 'models/sync_event.dart';
import 'models/sync_pull_report.dart';
import 'remote_event_applier.dart';
import 'sync_endpoint_config.dart';

class SyncPullService {
  SyncPullService({
    required SyncCheckpointDao syncCheckpointDao,
    required RemoteEventApplier remoteEventApplier,
    required SyncEndpointConfig endpointConfig,
    required LocalCommandContext commandContext,
    http.Client? client,
  }) : _syncCheckpointDao = syncCheckpointDao,
       _remoteEventApplier = remoteEventApplier,
       _endpointConfig = endpointConfig,
       _commandContext = commandContext,
       _client = client ?? http.Client();

  static const defaultLimit = 500;

  final SyncCheckpointDao _syncCheckpointDao;
  final RemoteEventApplier _remoteEventApplier;
  final SyncEndpointConfig _endpointConfig;
  final LocalCommandContext _commandContext;
  final http.Client _client;

  Future<SyncPullReport> pullIfBehind(int latestServerSequence) async {
    final currentCursor = await _syncCheckpointDao
        .obtenerLastFullPullServerSequence();

    if (latestServerSequence <= currentCursor) {
      return SyncPullReport.empty(lastCursor: currentCursor);
    }

    return pullAvailableEvents();
  }

  Future<SyncPullReport> pullAvailableEvents({int limit = defaultLimit}) async {
    var cursor = await _syncCheckpointDao.obtenerLastFullPullServerSequence();
    var total = 0;
    var hasMore = true;

    while (hasMore) {
      final page = await _fetchPage(since: cursor, limit: limit);
      if (page.events.isEmpty) {
        return SyncPullReport(total: total, lastCursor: cursor, hasMore: false);
      }

      final appliedCursor = _maxServerSequence(page.events);
      await _remoteEventApplier.applySyncedEvents(
        page.events,
        afterApply: () async {
          await _syncCheckpointDao.actualizarLastFullPullServerSequence(
            appliedCursor,
          );
        },
      );

      total += page.events.length;
      cursor = appliedCursor;
      hasMore = page.hasMore;
    }

    return SyncPullReport(total: total, lastCursor: cursor, hasMore: false);
  }

  Future<_PullPage> _fetchPage({required int since, required int limit}) async {
    final uri = Uri.parse('${_endpointConfig.baseUrl}/sync/pull').replace(
      queryParameters: {
        'device_id': _commandContext.deviceId,
        'since': '$since',
        'limit': '$limit',
      },
    );

    try {
      final response = await _client.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncPullException(
          'Error descargando eventos: ${response.statusCode} ${response.body}',
        );
      }

      return _decodePullPage(response.body);
    } on SyncPullException {
      rethrow;
    } catch (error) {
      throw SyncPullException('Error descargando eventos: $error');
    }
  }

  _PullPage _decodePullPage(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const SyncPullException('Respuesta invalida del servidor.');
    }

    final data = decoded.cast<String, Object?>();
    final rawEvents = data['events'];
    if (rawEvents is! List) {
      throw const SyncPullException('Respuesta sin arreglo events.');
    }

    final events = rawEvents
        .whereType<Map>()
        .map((event) => SyncEvent.fromJson(event.cast<String, Object?>()))
        .toList();

    return _PullPage(events: events, hasMore: data['has_more'] == true);
  }

  int _maxServerSequence(List<SyncEvent> events) {
    var maxSequence = 0;

    for (final event in events) {
      final serverSequence = event.serverSequence;
      if (serverSequence == null) {
        throw const SyncPullException('Evento remoto sin server_sequence.');
      }

      if (serverSequence > maxSequence) {
        maxSequence = serverSequence;
      }
    }

    return maxSequence;
  }
}

class _PullPage {
  const _PullPage({required this.events, required this.hasMore});

  final List<SyncEvent> events;
  final bool hasMore;
}
