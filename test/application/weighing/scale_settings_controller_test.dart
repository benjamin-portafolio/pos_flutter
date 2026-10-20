import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_exception.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';
import 'package:pos_flutter/application/weighing/scale_serial_settings.dart';
import 'package:pos_flutter/application/weighing/scale_session.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_settings.dart';
import 'package:pos_flutter/application/weighing/scale_settings_controller.dart';
import 'package:pos_flutter/application/weighing/scale_settings_exception.dart';

import '../../support/fake_scale_gateway.dart';
import '../../support/fake_scale_settings_store.dart';

void main() {
  ScaleProfile profile(String id, String port, {String alias = 'Caja'}) =>
      ScaleProfile(id: id, alias: alias, port: port, systemId: 'device-$id');
  final a = profile('a', 'COM8');
  final b = profile('b', 'COM9');
  late FakeScaleGateway gateway;
  late FakeScaleSettingsStore store;
  late ScaleSessionService service;
  late ScaleSettingsController controller;
  final busy = throwsA(
    isA<ScaleException>().having(
      (e) => e.failure,
      'failure',
      ScaleFailure.busy,
    ),
  );

  setUp(() async {
    gateway = FakeScaleGateway();
    store = FakeScaleSettingsStore();
    service = ScaleSessionService(gateway);
    controller = ScaleSettingsController(store, sessionService: () => service);
    await controller.load();
  });
  tearDown(() async {
    gateway.failClose = false;
    if (gateway.pendingOpen?.isCompleted == false) {
      gateway.pendingOpen!.complete();
    }
    if (gateway.pendingClose?.isCompleted == false) {
      gateway.pendingClose!.complete();
    }
    for (final read in gateway.reads) {
      if (!read.isCompleted) read.complete([]);
    }
    await controller.dispose();
    await service.dispose();
  });

  test('B11 normalizes profile, rejects required/invalid parameters', () {
    final normalized = profile(' a ', ' com8 ', alias: ' Caja ');
    expect(normalized.id, 'a');
    expect(normalized.port, 'COM8');
    expect(normalized.alias, 'Caja');
    expect(normalized.systemId, 'device- a');
    for (final invalid in [
      () => profile('', 'COM8'),
      () => profile('a', 'COM0'),
      () => profile('a', 'COM8', alias: ' '),
      () => ScaleProfile(id: 'a', alias: 'A', port: 'COM8', systemId: ' '),
      () => ScaleProfile(
        id: 'a',
        alias: 'A',
        port: 'COM8',
        systemId: 'a',
        serial: const ScaleSerialSettings(baudRate: 4800),
      ),
    ]) {
      expect(invalid, throwsA(isA<ScaleException>()));
    }
  });

  test(
    'B11 duplicate normalized destinations/ids and absent default reject',
    () {
      expect(
        () => ScaleSettings(profiles: [a, profile('x', ' com8 ')]),
        throwsArgumentError,
      );
      expect(
        () => ScaleSettings(profiles: [a, profile('a', 'COM99')]),
        throwsArgumentError,
      );
      expect(
        () => ScaleSettings(profiles: [a], defaultId: 'missing'),
        throwsArgumentError,
      );
    },
  );

  test(
    'B12/B13 serial mutations, explicit defaults and id-preserving edit',
    () async {
      expect(gateway.calls, isEmpty);
      await Future.wait([controller.upsert(a), controller.upsert(b)]);
      expect(controller.settings.profiles, hasLength(2));
      expect(controller.settings.defaultId, isNull);
      await controller.setDefault(' a ');
      await controller.upsert(profile('a', 'COM12', alias: 'Editada'));
      expect(controller.settings.defaultId, 'a');
      expect(controller.settings.profiles.first.port, 'COM12');
      await controller.setDefault(b.id);
      await controller.setDefault(null);
      expect(controller.settings.defaultId, isNull);
      await controller.setDefault(a.id);
      await controller.remove(a.id);
      expect(controller.settings.defaultId, isNull);
      expect(controller.settings.profiles.single.id, 'b');
      expect(gateway.calls, isEmpty);
    },
  );

  test('B11 duplicate save rejected, queue remains usable', () async {
    await controller.upsert(a);
    await expectLater(
      controller.upsert(profile('other', ' com8 ')),
      throwsArgumentError,
    );
    expect(store.saves, 1);
    await controller.upsert(b);
    expect(controller.settings.profiles, hasLength(2));
  });

  test(
    'B14 failed write/read preserves confirmed state, explicit recovery',
    () async {
      await controller.upsert(a);
      final confirmed = controller.settings;
      store.writeError = const ScaleSettingsException(
        ScaleSettingsFailure.writeFailed,
      );
      await expectLater(
        controller.upsert(b),
        throwsA(isA<ScaleSettingsException>()),
      );
      expect(controller.settings, same(confirmed));
      expect(controller.canEdit, isTrue);
      store.writeError = null;
      store.readError = const ScaleSettingsException(
        ScaleSettingsFailure.readFailed,
      );
      await controller.load();
      expect(controller.settings, same(confirmed));
      expect(controller.loadError!.canRecover, isFalse);
      await expectLater(controller.recover(), throwsStateError);
      store.readError = const ScaleSettingsException(
        ScaleSettingsFailure.corrupt,
      );
      await controller.load();
      expect(controller.canEdit, isFalse);
      store.writeError = const ScaleSettingsException(
        ScaleSettingsFailure.writeFailed,
      );
      await expectLater(
        controller.recover(),
        throwsA(isA<ScaleSettingsException>()),
      );
      expect(controller.settings, same(confirmed));
      expect(controller.loadError!.canRecover, isTrue);
      store.writeError = null;
      await controller.recover();
      expect(controller.settings.profiles, isEmpty);
      expect(controller.canEdit, isTrue);
    },
  );

  test(
    'B15/B07 active or closing session blocks changes; snapshot stays immutable',
    () async {
      await controller.upsert(a);
      gateway.pendingOpen = Completer<void>();
      gateway.pendingClose = Completer<void>();
      final session = service.open(a, owner: ScaleSessionOwner.sale);
      await expectLater(controller.upsert(profile('a', 'COM12')), busy);
      await expectLater(controller.remove(a.id), busy);
      final close = session.close();
      gateway.pendingOpen!.complete();
      await Future<void>.delayed(Duration.zero);
      await expectLater(controller.remove(a.id), busy);
      expect(session.profile, same(a));
      gateway.pendingClose!.complete();
      await close;
      await controller.upsert(profile('a', 'COM12'));
      expect(session.profile.port, 'COM8');
      expect(controller.settings.profiles.single.port, 'COM12');
    },
  );

  test(
    'B07 asynchronous replacement reserves idle service until commit',
    () async {
      store.pendingWrite = Completer<void>();
      final write = controller.upsert(a);
      await Future<void>.delayed(Duration.zero);
      expect(() => service.open(a, owner: ScaleSessionOwner.test), busy);
      expect(controller.settings.profiles, isEmpty);
      store.pendingWrite!.complete();
      await write;
      gateway.pendingOpen = Completer<void>();
      final session = service.open(a, owner: ScaleSessionOwner.test);
      final closing = session.close();
      gateway.pendingOpen!.complete();
      await closing;
    },
  );

  test('dispose drains queued saves and closes changes', () async {
    store.pendingWrite = Completer<void>();
    final write = controller.upsert(a);
    var disposed = false;
    final disposing = controller.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    store.pendingWrite!.complete();
    await write;
    await disposing;
    await expectLater(controller.upsert(b), throwsStateError);
  });
}
