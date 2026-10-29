import 'package:pos_flutter/application/sync/sync_capability_store.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/sale_adjustment_availability.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_health_service.dart';
import 'package:pos_flutter/data/local/sync/sync_capability_file_store.dart';

void main() {
  test(
    'unknown, compatible, restart offline, endpoint change, revoke and recover',
    () async {
      final dir = await Directory.systemTemp.createTemp('pos-capability-');
      addTearDown(() => dir.delete(recursive: true));
      final config = AppConfigController(
        AppConfig.initial.copyWith(mode: AppMode.serverSync),
      );
      addTearDown(config.dispose);
      final endpoint = SyncEndpointConfig(
        initialBaseUrl: 'http://localhost:1234',
      );
      var online = false, compatible = true, calls = 0, status = 200;
      final client = MockClient((_) async {
        calls++;
        if (!online) throw const SocketException('offline');
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'capabilities': compatible
                ? ['sale_adjustments_v1', 'sale_reconciliations_v1']
                : ['sale_adjustments_v1'],
          }),
          status,
        );
      });
      addTearDown(client.close);
      SaleAdjustmentAvailability installation() {
        final store = SyncCapabilityFileStore(
          directoryProvider: () async => dir,
        );
        return SaleAdjustmentAvailability(
          config: config,
          endpoint: endpoint,
          store: store,
          health: () => SyncHealthService(
            endpointConfig: endpoint,
            client: client,
            capabilityStore: store,
          ),
        );
      }

      var policy = installation();
      await expectLater(
        policy.requireCompatible(refresh: true),
        throwsStateError,
      );
      online = true;
      await policy.requireCompatible(refresh: true);
      online = false;
      policy = installation(); // real file, new controller/store after restart
      await policy.requireCompatible(refresh: true);
      endpoint.updateFromInput('localhost:5678');
      await expectLater(policy.requireCompatible(), throwsStateError);
      endpoint.updateFromInput('localhost:1234');
      await policy.requireCompatible();
      online = true;
      status = 503; // outage retains last successful knowledge
      await policy.requireCompatible(refresh: true);
      status = 200;
      compatible = false;
      await expectLater(
        policy.requireCompatible(refresh: true),
        throwsStateError,
      );
      online = false;
      await expectLater(
        installation().requireCompatible(refresh: true),
        throwsStateError,
      );
      online = true;
      compatible = true;
      await policy.requireCompatible(refresh: true);
      status = 404; // reachable but wrong server revokes cached permission
      await expectLater(
        policy.requireCompatible(refresh: true),
        throwsStateError,
      );
      final before = calls;
      config.update(config.config.copyWith(mode: AppMode.standalone));
      await policy.requireCompatible(refresh: true);
      expect(calls, before);
    },
  );

  test(
    'a failed persistence of incompatibility cannot authorize cached capture',
    () async {
      final config = AppConfigController(
        AppConfig.initial.copyWith(mode: AppMode.serverSync),
      );
      addTearDown(config.dispose);
      final endpoint = SyncEndpointConfig();
      final client = MockClient(
        (_) async => http.Response('{"status":"ok","capabilities":[]}', 200),
      );
      addTearDown(client.close);
      final store = _FailingCapabilityStore();
      final policy = SaleAdjustmentAvailability(
        config: config,
        endpoint: endpoint,
        store: store,
        health: () => SyncHealthService(
          endpointConfig: endpoint,
          client: client,
          capabilityStore: store,
        ),
      );
      await expectLater(
        policy.requireCompatible(refresh: true),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'corrupt or absent installation metadata fails closed; writes are atomic',
    () async {
      final dir = await Directory.systemTemp.createTemp('pos-capability-');
      addTearDown(() => dir.delete(recursive: true));
      final store = SyncCapabilityFileStore(directoryProvider: () async => dir);
      expect(await store.read('server'), isNull);
      await Future.wait(
        List.generate(8, (_) => store.write('server', ['sale_adjustments_v1'])),
      );
      expect(await store.read('server'), ['sale_adjustments_v1']);
      final file = (await dir.list().toList()).whereType<File>().single;
      await file.writeAsString('{broken');
      expect(await store.read('server'), isNull);
    },
  );
}

class _FailingCapabilityStore implements SyncCapabilityStore {
  @override
  Future<List<String>?> read(String endpoint) async => [
    'sale_adjustments_v1',
    'sale_reconciliations_v1',
  ];
  @override
  Future<void> write(String endpoint, List<String> capabilities) async {
    throw const FileSystemException('disk unavailable');
  }
}
