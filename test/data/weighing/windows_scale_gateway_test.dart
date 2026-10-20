import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_exception.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';
import 'package:pos_flutter/data/weighing/windows_scale_gateway.dart';

void main() {
  final profile = ScaleProfile(
    id: 'p',
    alias: 'test',
    port: 'COM27',
    systemId: 'USB\\test',
  );
  final devices = [
    {'port': 'COM27', 'name': 'USB Serial', 'systemId': 'USB\\test'},
  ];
  Matcher fails(ScaleFailure failure) =>
      isA<ScaleException>().having((e) => e.failure, 'failure', failure);

  test(
    'construction and unsupported platform never invoke Windows APIs',
    () async {
      var calls = 0;
      final gateway = WindowsScaleGateway(
        isWindows: false,
        operation: (_, _) async {
          calls++;
          throw StateError('Must not load a Windows DLL');
        },
      );
      expect(calls, 0);
      await expectLater(
        gateway.listDevices(),
        throwsA(fails(ScaleFailure.unsupportedPlatform)),
      );
      await expectLater(
        gateway.open(profile),
        throwsA(fails(ScaleFailure.unsupportedPlatform)),
      );
      await expectLater(
        gateway.readWeight(),
        throwsA(fails(ScaleFailure.unsupportedPlatform)),
      );
      await gateway.close();
      expect(calls, 0);
    },
  );

  test(
    'enumeration opens no serial destination; identity mismatch cannot retarget',
    () async {
      final calls = <String>[];
      final gateway = WindowsScaleGateway(
        isWindows: true,
        operation: (name, args) async {
          calls.add(name);
          return devices;
        },
      );
      expect((await gateway.listDevices()).single.port, 'COM27');
      final changed = ScaleProfile(
        id: 'p',
        alias: 'test',
        port: 'COM27',
        systemId: 'other',
      );
      await expectLater(
        gateway.open(changed),
        throwsA(fails(ScaleFailure.deviceChanged)),
      );
      expect(calls, ['list', 'list']);
      final absent = ScaleProfile(
        id: 'p',
        alias: 'test',
        port: 'COM99',
        systemId: 'other',
      );
      await expectLater(
        gateway.open(absent),
        throwsA(fails(ScaleFailure.deviceNotFound)),
      );
      await gateway.close();
    },
  );

  test(
    'close while native opening waits for handle and close acknowledgement',
    () async {
      final opening = Completer<Object?>();
      final closing = Completer<Object?>();
      final calls = <String>[];
      final gateway = WindowsScaleGateway(
        isWindows: true,
        operation: (name, args) async {
          calls.add(name);
          return switch (name) {
            'list' => devices,
            'open' => await opening.future,
            'close' => await closing.future,
            _ => throw StateError(name),
          };
        },
      );
      final opened = gateway.open(profile);
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final drained = gateway.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['list', 'open']);
      expect(closed, isFalse);
      opening.complete({'handle': 42, 'configured': true});
      await opened;
      await Future<void>.delayed(Duration.zero);
      expect(calls.last, 'close');
      await expectLater(
        gateway.open(profile),
        throwsA(fails(ScaleFailure.busy)),
      );
      closing.complete(true);
      await drained;
      expect(closed, isTrue);
    },
  );

  test('close during enumeration prevents subsequent CreateFile', () async {
    final listed = Completer<Object?>();
    final calls = <String>[];
    final gateway = WindowsScaleGateway(
      isWindows: true,
      operation: (name, _) async {
        calls.add(name);
        return listed.future;
      },
    );
    final opening = gateway.open(profile);
    final closing = gateway.close();
    listed.complete(devices);
    await opening;
    await closing;
    expect(calls, ['list']);
  });

  test(
    'pending native query cannot overlap or close its handle prematurely',
    () async {
      final query = Completer<Object?>();
      final calls = <String>[];
      final gateway = WindowsScaleGateway(
        isWindows: true,
        operation: (name, args) async {
          calls.add(name);
          return switch (name) {
            'list' => devices,
            'open' => {'handle': 42, 'configured': true},
            'query' => await query.future,
            'close' => true,
            _ => throw StateError(name),
          };
        },
      );
      await gateway.open(profile);
      final reading = gateway.readWeight();
      await expectLater(
        gateway.readWeight(),
        throwsA(fails(ScaleFailure.busy)),
      );
      final closing = gateway.close();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['list', 'open', 'query']);
      query.complete(ascii.encode('  0.278 kg\r'));
      expect((await reading).single.weight!.grams, 278);
      await closing;
      expect(calls.last, 'close');
    },
  );

  test(
    'configuration failure retains handle; failed close is retryable',
    () async {
      var closeCount = 0;
      final gateway = WindowsScaleGateway(
        isWindows: true,
        operation: (name, args) async {
          return switch (name) {
            'list' => devices,
            'open' => {'handle': 42, 'configured': false, 'error': 87},
            'close' => ++closeCount > 1,
            _ => throw StateError(name),
          };
        },
      );
      await expectLater(
        gateway.open(profile),
        throwsA(fails(ScaleFailure.invalidConfiguration)),
      );
      await expectLater(
        gateway.close(),
        throwsA(fails(ScaleFailure.closeFailed)),
      );
      await expectLater(
        gateway.open(profile),
        throwsA(fails(ScaleFailure.busy)),
      );
      await gateway.close();
      expect(closeCount, 2);
    },
  );

  test('refresh between queries cannot interrupt the active lease', () async {
    var listings = 0;
    final gateway = WindowsScaleGateway(
      isWindows: true,
      operation: (name, _) async {
        switch (name) {
          case 'list':
            listings++;
            return devices;
          case 'open':
            return {'handle': 42, 'configured': true};
          case 'query':
            return ascii.encode('  0.278 kg\r');
          case 'close':
            return true;
          default:
            throw StateError(name);
        }
      },
    );
    await gateway.open(profile);
    expect((await gateway.readWeight()).single.isValid, isTrue);
    await expectLater(gateway.listDevices(), throwsA(fails(ScaleFailure.busy)));
    expect((await gateway.readWeight()).single.weight!.grams, 278);
    expect(listings, 1);
    await gateway.close();
    expect((await gateway.listDevices()).single.port, profile.port);
    expect(listings, 2);
  });

  for (final failure in [
    ScaleFailure.busy,
    ScaleFailure.accessDenied,
    ScaleFailure.deviceNotFound,
    ScaleFailure.transportError,
  ]) {
    test(
      'native $failure is preserved, no retry and no invented handle',
      () async {
        final calls = <String>[];
        final gateway = WindowsScaleGateway(
          isWindows: true,
          operation: (name, _) async {
            calls.add(name);
            if (name == 'list') return devices;
            throw ScaleException(failure, nativeCode: 5);
          },
        );
        await expectLater(gateway.open(profile), throwsA(fails(failure)));
        await gateway.close();
        expect(calls, ['list', 'open']);
      },
    );
  }

  test(
    'partial response times out and parser is reset before a new session',
    () async {
      var queryCount = 0;
      final gateway = WindowsScaleGateway(
        isWindows: true,
        operation: (name, _) async {
          return switch (name) {
            'list' => devices,
            'open' => {'handle': 42, 'configured': true},
            'query' => ascii.encode(++queryCount == 1 ? '  0.' : '278 kg\r'),
            'close' => true,
            _ => throw StateError(name),
          };
        },
      );
      await gateway.open(profile);
      await expectLater(
        gateway.readWeight(),
        throwsA(fails(ScaleFailure.noResponse)),
      );
      await gateway.close();
      await gateway.open(profile);
      expect(
        (await gateway.readWeight()).single.failure,
        ScaleFailure.invalidFrame,
      );
      await gateway.close();
    },
  );
}
