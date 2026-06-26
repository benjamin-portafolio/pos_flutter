import 'package:socket_io_client/socket_io_client.dart' as io;

import '../commands/local_command_context.dart';
import 'sync_endpoint_config.dart';

class SyncSocketListener {
  SyncSocketListener({
    required SyncEndpointConfig endpointConfig,
    required LocalCommandContext commandContext,
  }) : _endpointConfig = endpointConfig,
       _commandContext = commandContext;

  static const eventsAvailableMessage = 'sync:events_available';

  final SyncEndpointConfig _endpointConfig;
  final LocalCommandContext _commandContext;

  io.Socket? _socket;
  String? _connectedBaseUrl;

  bool get isActive => _socket != null;

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
      socket.emit('sync:join', {
        'device_id': _commandContext.deviceId,
        'last_full_pull_server_sequence': null,
      });
    });

    socket.on(eventsAvailableMessage, (_) {
      // ignore: avoid_print
      print('Se ha recibido un evento del servidor.');
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
}
