// Durable transfer against the isolated real NestJS/PG receiver.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_attempt_store.dart';
import 'package:pos_flutter/application/recovery/recovery_transfer_service.dart';
import 'package:pos_flutter/application/recovery/recovery_transport.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/data/local/recovery/http_recovery_transport.dart';

class LostResponse implements RecoveryTransport {
  LostResponse(this.inner, this.phase);
  final RecoveryTransport inner;
  final String phase;
  bool dropped = false;
  @override
  Future<Map<String, Object?>> request(
    String method,
    String path, {
    List<int>? bytes,
    Map<String, String> headers = const {},
  }) async {
    final result = await inner.request(
      method,
      path,
      bytes: bytes,
      headers: headers,
    );
    final matches = switch (phase) {
      'start' => path == '/recovery/sessions',
      'chunk' => path.contains('/chunks/'),
      'validate' => path.endsWith('/validate'),
      'finalize' => path.endsWith('/finalize'),
      _ => false,
    };
    if (matches && !dropped) {
      dropped = true;
      throw const SocketException(
        'Synthetic lost response after remote commit',
      );
    }
    return result;
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
    'durable recovery transfer resumes the same package after a lost response',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final inputPath = Platform.environment['POS_RECOVERY_S5_TRANSFER']!;
      if (!inputPath.startsWith('/tmp/pos-recovery-s4-')) {
        throw StateError('Isolated fixture required');
      }
      final input = jsonDecode(await File(inputPath).readAsString()) as Map;
      final uri = Uri.parse(input['url'] as String);
      if (uri.host != '127.0.0.1') throw StateError('Loopback required');
      RecoveryTransport transport() => HttpRecoveryTransport(
        mode: AppMode.serverSync,
        destination: uri,
        server: input['server'] as String,
        generation: input['generation'] as String,
        token: input['token'] as String,
      );
      final store = RecoveryAttemptStore(
        Directory('${File(inputPath).parent.path}/attempt'),
      );
      var service = RecoveryTransferService(store);
      await service.begin(
        mode: AppMode.serverSync,
        package: Directory(input['package'] as String),
        destination: uri,
        server: input['server'] as String,
        generation: input['generation'] as String,
        token: input['token'] as String,
      );
      final phase = input['phase'] as String;
      if (phase == 'abort') {
        final connection = transport();
        addTearDown(connection.close);
        expect(
          (await service.run(
            connection,
            cancellation: RecoveryCancellation(),
          ))['state'],
          'ready_to_commit',
        );
        final aborted = await service.run(
          connection,
          cancellation: RecoveryCancellation(),
          abort: true,
        );
        expect(aborted['state'], 'aborted');
        final reopened = RecoveryTransferService(
          RecoveryAttemptStore(store.directory),
        );
        expect(
          (await reopened.run(
            connection,
            cancellation: RecoveryCancellation(),
          ))['state'],
          'aborted',
        );
        return;
      }
      var connection = LostResponse(
        transport(),
        phase == 'finalize' ? 'none' : phase,
      );
      if (phase != 'finalize') {
        await expectLater(
          service.run(connection, cancellation: RecoveryCancellation()),
          throwsA(isA<SocketException>()),
        );
      } else {
        expect(
          (await service.run(
            connection,
            cancellation: RecoveryCancellation(),
          ))['state'],
          'ready_to_commit',
        );
      }
      connection.close();
      // New coordinator and transport model a fresh process opening the journal.
      service = RecoveryTransferService(RecoveryAttemptStore(store.directory));
      connection = LostResponse(
        transport(),
        phase == 'finalize' ? 'finalize' : 'none',
      );
      if (phase == 'finalize') {
        await expectLater(
          service.run(
            connection,
            cancellation: RecoveryCancellation(),
            publish: true,
          ),
          throwsA(isA<SocketException>()),
        );
      } else {
        expect(
          (await service.run(
            connection,
            cancellation: RecoveryCancellation(),
          ))['state'],
          'ready_to_commit',
        );
      }
      connection.close();
      final resumed = transport();
      addTearDown(resumed.close);
      final completed = await RecoveryTransferService(
        store,
      ).run(resumed, cancellation: RecoveryCancellation(), publish: true);
      expect(completed['state'], 'completed');
      final receipt = (completed['progress'] as Map)['receipt'];
      expect(receipt, isA<Map>());
      final queried = await RecoveryTransferService(
        store,
      ).run(resumed, cancellation: RecoveryCancellation(), abort: true);
      expect(queried['state'], 'completed');
      expect((queried['progress'] as Map)['receipt'], receipt);
    },
  );
}
