import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_exception.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';
import 'package:pos_flutter/application/weighing/scale_session.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_settings_controller.dart';
import 'package:pos_flutter/data/local/weighing/scale_settings_file_store.dart';
import 'package:pos_flutter/data/weighing/windows_scale_gateway.dart';
import 'package:pos_flutter/data/weighing/windows_scale_native.dart';

Future<Object?> _invokeNative(String name, Map<String, Object?> args) =>
    Isolate.run(() => windowsScaleNative(name, args));

/// Opt-in hardware verification. Uses only temporary settings and weight queries.
/// Specify BOTH SCALE_TEST_PORT and SCALE_TEST_SYSTEM_ID for an identified Rhino.
void main() {
  final port = Platform.environment['SCALE_TEST_PORT'];
  final systemId = Platform.environment['SCALE_TEST_SYSTEM_ID'];
  test(
    'B10/B07/B15 physical configuration with isolated settings',
    () async {
      final native = <Map<String, Object?>>[];
      final gateway = WindowsScaleGateway(
        operation: (name, args) async {
          final result = await _invokeNative(name, args);
          native.add({
            'operation': name,
            if (name == 'list') 'devices': result,
            if (name == 'query') 'bytes': result,
            if (name == 'close') 'closed': result,
          });
          return result;
        },
      );
      final service = ScaleSessionService(gateway);
      final directory = await Directory.systemTemp.createTemp(
        'scale_hardware_',
      );
      final store = ScaleSettingsFileStore(
        directoryProvider: () async => directory,
      );
      final controller = ScaleSettingsController(
        store,
        sessionService: () => service,
      );
      try {
        await controller.load();
        expect(service.active, isNull);
        expect(native, isEmpty);
        final devices = await gateway.listDevices();
        final device = devices.singleWhere(
          (d) =>
              d.port.toUpperCase() == port!.toUpperCase() &&
              d.systemId.toUpperCase() == systemId!.toUpperCase(),
        );
        final profile = ScaleProfile(
          id: 'hardware-test',
          alias: 'Rhino de prueba',
          port: device.port,
          systemId: device.systemId,
        );
        final session = service.open(profile, owner: ScaleSessionOwner.test);
        expect(session.snapshot.measurement, isNull);
        final sample = await session.updates
            .firstWhere((s) => s.measurement?.weight != null)
            .timeout(const Duration(seconds: 8));
        expect(sample.measurement!.weight!.unit.name, 'kg');
        final busy = throwsA(
          isA<ScaleException>().having(
            (e) => e.failure,
            'failure',
            ScaleFailure.busy,
          ),
        );
        expect(
          () => service.open(profile, owner: ScaleSessionOwner.sale),
          busy,
        );
        await expectLater(controller.upsert(profile), busy);
        await expectLater(controller.remove(profile.id), busy);
        await session.close();
        expect(service.active, isNull);
        expect(native.last, {'operation': 'close', 'closed': true});
        await controller.upsert(profile);
        expect(controller.settings.defaultId, isNull);
        await controller.setDefault(profile.id);
        final reloaded = await ScaleSettingsFileStore(
          directoryProvider: () async => directory,
        ).readSettings();
        expect(reloaded.defaultId, profile.id);
        expect(reloaded.profiles.single.systemId, profile.systemId);
        final next = service.open(
          reloaded.profiles.single,
          owner: ScaleSessionOwner.test,
        );
        expect(next.snapshot.measurement, isNull);
        // Close during connection; the service must drain it before freeing.
        await next.close();
        expect(service.active, isNull);
        // Captures describe bytes and interpreted values, not display/calibration.
        // ignore: avoid_print
        print(
          jsonEncode({
            'port': profile.port,
            'systemId': profile.systemId,
            'grams': sample.measurement!.weight!.grams,
            'failure': sample.failure?.name,
            'defaultAfterReload': reloaded.defaultId,
            'settings': jsonDecode(
              await File(
                '${directory.path}/scale_settings.json',
              ).readAsString(),
            ),
            'native': native,
          }),
        );
      } finally {
        await service.dispose();
        await controller.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows || port == null || systemId == null,
  );
}
