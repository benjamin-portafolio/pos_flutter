import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_network_gate.dart';
import 'package:pos_flutter/application/sync/sync_persistence.dart';
import 'package:pos_flutter/application/sync/sync_socket_listener.dart';
import 'package:pos_flutter/data/local/sync/guarded_sync_client.dart';

class _UnusedPersistence implements SyncPersistence {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No debe leer persistencia');
}

void main() {
  test(
    'standalone bloquea todo HTTP operativo y no inicia WebSocket',
    () async {
      var calls = 0;
      final gate = SyncNetworkGate(isServerSync: () => false);
      final client = GuardedSyncClient(
        gate,
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      for (final path in [
        'health',
        'push',
        'pull',
        'preflight',
        'conflicts/report',
      ]) {
        await expectLater(
          client.get(Uri.parse('https://original.test/sync/$path')),
          throwsStateError,
        );
      }
      final socket = SyncSocketListener(
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'https://original.test',
        ),
        commandContext: const LocalCommandContext(deviceId: 'a', userId: 'u'),
        syncPersistence: _UnusedPersistence(),
        allowsNetwork: () => gate.allowsNetwork,
      );
      socket.start();
      expect(socket.isActive, false);
      expect(calls, 0);
    },
  );

  test(
    'pausa espera la respuesta iniciada y bloquea nuevos envíos hasta liberar todas las pausas',
    () async {
      final body = StreamController<List<int>>();
      final started = Completer<void>();
      var calls = 0;
      final gate = SyncNetworkGate(isServerSync: () => true);
      final client = GuardedSyncClient(
        gate,
        MockClient.streaming((_, _) async {
          calls++;
          started.complete();
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      addTearDown(client.close);
      final old = client.get(Uri.parse('https://original.test/sync/health'));
      await started.future;
      var drained = false;
      final pause = gate.pause().then((_) => drained = true);
      final nested = gate.pause();
      await expectLater(
        client.post(Uri.parse('https://original.test/sync/push')),
        throwsStateError,
      );
      expect(drained, false);
      body.add([123, 125]);
      await body.close();
      await old;
      await pause;
      await nested;
      expect(drained, true);
      gate.resume();
      expect(gate.allowsNetwork, false);
      gate.resume();
      expect(gate.allowsNetwork, true);
      expect(calls, 1);
    },
  );

  test('fallo de transporte libera la espera', () async {
    final gate = SyncNetworkGate(isServerSync: () => true);
    final client = GuardedSyncClient(
      gate,
      MockClient((_) async => throw http.ClientException('fixture')),
    );
    addTearDown(client.close);
    await expectLater(
      client.get(Uri.parse('https://original.test')),
      throwsA(isA<http.ClientException>()),
    );
    await gate.pause();
    gate.resume();
    expect(gate.allowsNetwork, true);
  });
}
