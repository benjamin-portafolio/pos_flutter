import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';
import 'package:pos_flutter/application/weighing/scale_exception.dart';
import 'package:pos_flutter/application/weighing/scale_gateway.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';
import 'package:pos_flutter/application/weighing/scale_session.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_settings_controller.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/config/app_config_file_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import '../../support/fake_scale_gateway.dart';
import '../../support/fake_printer_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late FakeScaleGateway gateway;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_weighing_di_');
    messenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => directory.path,
    );
    gateway = FakeScaleGateway();
  });
  tearDown(() async {
    gateway.failClose = false;
    if (gateway.pendingClose?.isCompleted == false) {
      gateway.pendingClose!.complete();
    }
    for (final read in gateway.reads) {
      if (!read.isCompleted) read.complete([]);
    }
    if (getIt.isRegistered<ScaleSessionService>()) {
      await getIt<ScaleSessionService>().dispose();
    }
    if (getIt.isRegistered<AppDatabase>()) await getIt<AppDatabase>().close();
    if (getIt.isRegistered<AppConfigController>()) {
      await getIt<AppConfigController>().dispose();
    }
    await getIt.reset();
    messenger.setMockMethodCallHandler(pathProvider, null);
    await directory.delete(recursive: true);
  });
  final profile = ScaleProfile(
    id: 'p',
    alias: 'test',
    port: 'COM17',
    systemId: 'test',
  );

  Future<void> setup() async {
    await setupDependencyInjection();
    await getIt.unregister<PrinterGateway>();
    getIt.registerSingleton<PrinterGateway>(FakePrinterGateway());
  }

  for (final mode in AppMode.values) {
    test(
      'shared lazy weighing in ${mode.name}; DI restart drains close',
      () async {
        var networkCalls = 0;
        await HttpOverrides.runZoned(
          () async {
            await AppConfigFileStore().saveConfig(
              AppConfig.initial.copyWith(mode: mode),
            );
            await setup();
            final settings = getIt<ScaleSettingsController>();
            expect(settings.loaded, isTrue);
            expect(settings.loadError, isNull);
            // The real gateway was registered but never resolved; no enumeration
            // or connection at startup, nor when resolving the shared service.
            await getIt.unregister<ScaleGateway>();
            getIt.registerSingleton<ScaleGateway>(gateway);
            final service = getIt<ScaleSessionService>();
            expect(getIt<ScaleSessionService>(), same(service));
            expect(gateway.calls, isEmpty);
            await settings.upsert(profile);
            await settings.setDefault(profile.id);
            expect(gateway.calls, isEmpty);
            gateway.pendingOpen = Completer<void>();
            gateway.pendingClose = Completer<void>();
            service.open(profile, owner: ScaleSessionOwner.test);
            var restarted = false;
            final restarting = restartDependencyInjection(
              previousConfig: AppConfig.initial,
            ).then((_) => restarted = true);
            await Future<void>.delayed(Duration.zero);
            gateway.pendingOpen!.complete();
            await Future<void>.delayed(Duration.zero);
            expect(restarted, isFalse);
            expect(getIt<ScaleSessionService>(), same(service));
            gateway.pendingClose!.complete();
            gateway.pendingClose = null;
            await restarting;
            expect(gateway.calls, ['open:COM17', 'close']);
            expect(getIt<ScaleSessionService>(), isNot(same(service)));
            expect(
              getIt<ScaleSettingsController>().settings.defaultId,
              profile.id,
            );
            expect(
              getIt<ScaleSettingsController>().settings.profiles.single.port,
              profile.port,
            );
            await expectLater(settings.upsert(profile), throwsStateError);
          },
          createHttpClient: (_) {
            networkCalls++;
            throw StateError('Weighing must not start synchronization');
          },
        );
        expect(networkCalls, 0);
      },
    );
  }
  test('failed close blocks DI reset and keeps shared lease owned', () async {
    await setup();
    await getIt.unregister<ScaleGateway>();
    getIt.registerSingleton<ScaleGateway>(gateway);
    final service = getIt<ScaleSessionService>();
    gateway.pendingOpen = Completer<void>();
    gateway.failClose = true;
    service.open(profile, owner: ScaleSessionOwner.test);
    final restarting = expectLater(
      restartDependencyInjection(previousConfig: AppConfig.initial),
      throwsA(isA<ScaleException>()),
    );
    await Future<void>.delayed(Duration.zero);
    gateway.pendingOpen!.complete();
    await restarting;
    expect(getIt<ScaleSessionService>(), same(service));
    expect(getIt<ScaleGateway>(), same(gateway));
    expect(service.active, isNotNull);
  });
}
