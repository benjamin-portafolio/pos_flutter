import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_exception.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_measurement.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';
import 'package:pos_flutter/application/weighing/scale_serial_settings.dart';
import 'package:pos_flutter/application/weighing/scale_session.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_session_snapshot.dart';
import 'package:pos_flutter/application/weighing/scale_weight.dart';
import '../../support/fake_scale_gateway.dart';

void main() {
  final profile = ScaleProfile(
    id: 'p1',
    alias: 'Rhino',
    port: 'COM17',
    systemId: 'test-device',
  );
  final positive = ScaleMeasurement(
    weight: ScaleWeight(
      coefficient: BigInt.from(278),
      decimalPlaces: 3,
      unit: ScaleUnit.kg,
      grams: 278,
    ),
  );
  Matcher fails(ScaleFailure failure) =>
      isA<ScaleException>().having((e) => e.failure, 'failure', failure);

  test(
    'profile normalizes destination and rejects empty/invalid parameters',
    () {
      final normalized = ScaleProfile(
        id: ' p ',
        alias: ' test ',
        port: ' com17 ',
        systemId: ' USB\\id ',
      );
      expect(normalized.port, 'COM17');
      expect(normalized.alias, 'test');
      expect(normalized.systemId, 'USB\\id');
      for (final port in ['', 'COM0', 'COM1/other', r'\\.\COM1', 'CH340']) {
        expect(
          () => ScaleProfile(id: 'p', alias: 't', port: port, systemId: 'd'),
          throwsA(fails(ScaleFailure.invalidConfiguration)),
        );
      }
      expect(
        () => ScaleProfile(id: '', alias: 't', port: 'COM1', systemId: 'd'),
        throwsA(fails(ScaleFailure.invalidConfiguration)),
      );
      expect(
        () => ScaleProfile(id: 'p', alias: '', port: 'COM1', systemId: 'd'),
        throwsA(fails(ScaleFailure.invalidConfiguration)),
      );
      expect(
        () => ScaleProfile(id: 'p', alias: 't', port: 'COM1', systemId: ''),
        throwsA(fails(ScaleFailure.invalidConfiguration)),
      );
      expect(
        () => ScaleProfile(
          id: 'p',
          alias: 't',
          port: 'COM1',
          systemId: 'd',
          serial: const ScaleSerialSettings(baudRate: 4800),
        ),
        throwsA(fails(ScaleFailure.invalidConfiguration)),
      );
    },
  );

  testWidgets('exclusive lease survives pending open and native close', (
    tester,
  ) async {
    final gateway = FakeScaleGateway()
      ..pendingOpen = Completer<void>()
      ..pendingClose = Completer<void>();
    final service = ScaleSessionService(gateway);
    expect(gateway.calls, isEmpty);
    final first = service.open(profile, owner: ScaleSessionOwner.test);
    expect(
      () => service.open(profile, owner: ScaleSessionOwner.sale),
      throwsA(fails(ScaleFailure.busy)),
    );
    var closed = false;
    final closing = first.close().then((_) => closed = true);
    await tester.pump();
    expect(closed, isFalse);
    expect(gateway.calls, ['open:COM17']);
    gateway.pendingOpen!.complete();
    await tester.pump();
    expect(gateway.calls, ['open:COM17', 'close']);
    expect(service.active, same(first));
    expect(gateway.reads, isEmpty);
    gateway.pendingClose!.complete();
    await closing;
    expect(service.active, isNull);
    final second = service.open(profile, owner: ScaleSessionOwner.sale);
    expect(second.id, isNot(first.id));
    expect(second.snapshot.measurement, isNull);
    await second.close();
    await service.dispose();
  });

  testWidgets(
    'one pending query, close discards late sample before next owner',
    (tester) async {
      final gateway = FakeScaleGateway();
      final service = ScaleSessionService(gateway);
      final first = service.open(profile, owner: ScaleSessionOwner.test);
      final observed = <ScaleSessionSnapshot>[];
      first.updates.listen(observed.add);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(gateway.reads, hasLength(1));
      final closing = first.close();
      await tester.pump();
      expect(service.active, same(first));
      gateway.reads.single.complete([positive]);
      await closing;
      expect(observed.any((s) => s.hasUsableWeight), isFalse);
      expect(first.hasFreshWeight, isFalse);
      final second = service.open(profile, owner: ScaleSessionOwner.sale);
      await tester.pump();
      expect(second.snapshot.measurement, isNull);
      expect(second.snapshot.sequence, 0);
      gateway.reads.last.complete([positive]);
      await tester.pump();
      expect(second.hasFreshWeight, isTrue);
      await second.close();
    },
  );

  testWidgets('monotonic expiry invalidates without new data; paced requests', (
    tester,
  ) async {
    var now = Duration.zero;
    final gateway = FakeScaleGateway();
    final service = ScaleSessionService(gateway, now: () => now);
    final session = service.open(profile, owner: ScaleSessionOwner.sale);
    await tester.pump();
    gateway.reads.single.complete([positive]);
    await tester.pump();
    expect(session.snapshot.receivedAt, Duration.zero);
    expect(session.hasFreshWeight, isTrue);
    now += const Duration(milliseconds: 249);
    await tester.pump(const Duration(milliseconds: 249));
    expect(gateway.reads, hasLength(1));
    now += const Duration(milliseconds: 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(gateway.reads, hasLength(2));
    now = const Duration(seconds: 2);
    // A synchronous read of freshness also rejects before the timer is pumped.
    expect(session.hasFreshWeight, isFalse);
    await tester.pump(const Duration(milliseconds: 1750));
    expect(session.snapshot.failure, ScaleFailure.stale);
    expect(session.snapshot.measurement, isNull);
    expect(gateway.reads, hasLength(2));
    final closing = session.close();
    gateway.reads.last.complete([positive]);
    await closing;
  });

  for (final failure in [
    ScaleFailure.nonPositive,
    ScaleFailure.invalidFrame,
    ScaleFailure.unsupportedUnit,
    ScaleFailure.overflow,
  ]) {
    testWidgets('$failure immediately replaces a prior positive sample', (
      tester,
    ) async {
      final gateway = FakeScaleGateway();
      final service = ScaleSessionService(gateway);
      final session = service.open(profile, owner: ScaleSessionOwner.test);
      await tester.pump();
      gateway.reads.single.complete([
        positive,
        ScaleMeasurement(failure: failure),
      ]);
      await tester.pump();
      expect(session.hasFreshWeight, isFalse);
      expect(session.snapshot.failure, failure);
      expect(session.snapshot.sequence, 2);
      await session.close();
    });
  }

  testWidgets(
    'transport error auto-closes and never retries a weight request',
    (tester) async {
      final gateway = FakeScaleGateway();
      final service = ScaleSessionService(gateway);
      final session = service.open(profile, owner: ScaleSessionOwner.test);
      await tester.pump();
      gateway.reads.single.completeError(
        const ScaleException(ScaleFailure.noResponse),
      );
      await tester.pump();
      expect(service.active, isNull);
      expect(session.snapshot.state, ScaleSessionState.closed);
      expect(session.snapshot.failure, ScaleFailure.noResponse);
      expect(gateway.reads, hasLength(1));
      await session.close();
    },
  );

  testWidgets('failed native close retains lease and disposal until retry', (
    tester,
  ) async {
    final gateway = FakeScaleGateway()
      ..pendingOpen = Completer<void>()
      ..failClose = true;
    final service = ScaleSessionService(gateway);
    final session = service.open(profile, owner: ScaleSessionOwner.test);
    final closing = expectLater(
      service.dispose(),
      throwsA(fails(ScaleFailure.closeFailed)),
    );
    gateway.pendingOpen!.complete();
    await tester.pump();
    await closing;
    expect(service.active, same(session));
    expect(
      () => service.open(profile, owner: ScaleSessionOwner.sale),
      throwsA(fails(ScaleFailure.disposed)),
    );
    gateway.failClose = false;
    await service.dispose();
    expect(service.active, isNull);
  });

  testWidgets(
    'a reading listener may close the lease without reentrant events',
    (tester) async {
      final gateway = FakeScaleGateway();
      final service = ScaleSessionService(gateway);
      final session = service.open(profile, owner: ScaleSessionOwner.test);
      Future<void>? closed;
      session.updates.listen((snapshot) {
        if (snapshot.hasUsableWeight) closed = session.close();
      });
      await tester.pump();
      gateway.reads.single.complete([positive]);
      await tester.pump();
      await closed;
      expect(service.active, isNull);
      expect(session.hasFreshWeight, isFalse);
      expect(gateway.reads, hasLength(1));
    },
  );

  testWidgets('failed close keeps other owners busy until a successful retry', (
    tester,
  ) async {
    final gateway = FakeScaleGateway()
      ..pendingOpen = Completer<void>()
      ..failClose = true;
    final service = ScaleSessionService(gateway);
    final session = service.open(profile, owner: ScaleSessionOwner.test);
    final closing = expectLater(
      session.close(),
      throwsA(fails(ScaleFailure.closeFailed)),
    );
    gateway.pendingOpen!.complete();
    await tester.pump();
    await closing;
    expect(
      () => service.open(profile, owner: ScaleSessionOwner.sale),
      throwsA(fails(ScaleFailure.busy)),
    );
    gateway.failClose = false;
    await session.close();
    expect(service.active, isNull);
  });
}
