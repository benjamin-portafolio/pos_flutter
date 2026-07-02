import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../commands/local_command_context.dart';
import '../../data/local/drift/app_database.dart';
import 'sync_endpoint_config.dart';

class SyncSocketListener {
  SyncSocketListener({
    required SyncEndpointConfig endpointConfig,
    required LocalCommandContext commandContext,
    required SyncCheckpointDao syncCheckpointDao,
  }) : _endpointConfig = endpointConfig,
       _commandContext = commandContext,
       _syncCheckpointDao = syncCheckpointDao;

  static const eventsAvailableMessage = 'sync:events_available';

  final SyncEndpointConfig _endpointConfig;
  final LocalCommandContext _commandContext;
  final SyncCheckpointDao _syncCheckpointDao;
  final _eventsAvailableController =
      StreamController<SyncEventsAvailableNotice>.broadcast();

  io.Socket? _socket;
  String? _connectedBaseUrl;

  bool get isActive => _socket != null;

  Stream<SyncEventsAvailableNotice> get eventsAvailable =>
      _eventsAvailableController.stream;

  void start() {
    final baseUrl = _endpointConfig.baseUrl;
    if (_socket != null && _connectedBaseUrl == baseUrl) return;

    stop();

    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setQuery({'device_id': _commandContext.deviceId})
          .build(),
    );

    socket.onConnect((_) {
      unawaited(_joinSyncRoom(socket));
    });

    socket.on(eventsAvailableMessage, (payload) {
      final notice = _parseEventsAvailableNotice(payload);
      if (notice == null) return;
      if (notice.sourceDeviceId == _commandContext.deviceId) return;

      _eventsAvailableController.add(notice);
    });

    _socket = socket;
    _connectedBaseUrl = baseUrl;
    socket.connect();
  }

  void reconnect() {
    stop();
    start();
  }

  void reconnectIfActive() {
    if (!isActive) return;

    reconnect();
  }

  void stop() {
    final socket = _socket;
    if (socket == null) return;

    socket.off(eventsAvailableMessage);
    socket.dispose();
    _socket = null;
    _connectedBaseUrl = null;
  }

  Future<void> _joinSyncRoom(io.Socket socket) async {
    final lastFullPullServerSequence = await _syncCheckpointDao
        .obtenerLastFullPullServerSequence();

    if (_socket != socket) return;

    socket.emit('sync:join', {
      'device_id': _commandContext.deviceId,
      'last_full_pull_server_sequence': lastFullPullServerSequence,
    });
  }

  SyncEventsAvailableNotice? _parseEventsAvailableNotice(Object? payload) {
    if (payload is! Map) return null;

    final data = payload.cast<String, Object?>();
    final latestServerSequence = _readInt(data['latest_server_sequence']);
    if (latestServerSequence == null) return null;

    return SyncEventsAvailableNotice(
      latestServerSequence: latestServerSequence,
      eventTypes: _readStringList(data['event_types']),
      sourceDeviceId: data['source_device_id'] as String?,
    );
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  List<String> _readStringList(Object? value) {
    if (value is! List) return const [];

    return value.whereType<String>().toList(growable: false);
  }
}

class SyncEventsAvailableNotice {
  const SyncEventsAvailableNotice({
    required this.latestServerSequence,
    required this.eventTypes,
    required this.sourceDeviceId,
  });

  final int latestServerSequence;
  final List<String> eventTypes;
  final String? sourceDeviceId;
}
