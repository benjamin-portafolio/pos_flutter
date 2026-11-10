import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/recovery/recovery_attempt_store.dart';
import 'package:pos_flutter/application/recovery/recovery_transfer_service.dart';

void main() {
  test(
    'invalid archived journal is rejected before moving the selected attempt',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'pos-attempt-invalid-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = RecoveryAttemptStore(Directory('${root.path}/attempt'));
      await store.directory.create();
      final history = Directory('${root.path}/history');
      final archived = Directory(
        '${history.path}/10000000-0000-4000-8000-000000000001-1794286800000',
      );
      await archived.create(recursive: true);
      await File('${archived.path}/attempt.json').writeAsString('[]');
      await expectLater(
        RecoveryAttemptStore(archived).read(),
        throwsFormatException,
      );
      await expectLater(
        RecoveryTransferService(store).reopen(
          history,
          archived.uri.pathSegments.where((s) => s.isNotEmpty).last,
        ),
        throwsFormatException,
      );
      expect(await store.directory.exists(), isTrue);
      expect(await File('${archived.path}/attempt.json').readAsString(), '[]');
    },
  );

  test(
    'terminal attempts retain all evidence and can be reopened without a new package or identity',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'pos-attempt-history-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = RecoveryAttemptStore(Directory('${root.path}/attempt')),
          service = RecoveryTransferService(
            RecoveryAttemptStore(Directory('${root.path}/attempt')),
          ),
          history = Directory('${root.path}/history');
      final original = <String, Object?>{
        'journal_version': 1,
        'package_id': '10000000-0000-4000-8000-000000000001',
        'recovery_id': 'original-attempt',
        'manifest_digest': 'original-digest',
        'recovery_token': 'original-scoped-token',
        'state': 'receiving',
        'prepared_source': {'snapshot_path': '/private/original.sqlite'},
        'progress': {'receipt': null},
      };
      await store.write(original);
      await expectLater(service.archive(history), throwsStateError);
      expect(await store.read(), original);
      await store.write({
        ...original,
        'state': 'completed',
        'progress': {
          'receipt': {'dataset_id': 'published-dataset'},
        },
      });
      final bytes = await store.file.readAsString();
      await service.archive(history);
      expect(await store.read(), isNull);
      final archived = (await history.list().toList()).single;
      expect(await File('${archived.path}/attempt.json').readAsString(), bytes);
      final key = archived.uri.pathSegments.where((s) => s.isNotEmpty).last;
      await service.reopen(history, key);
      expect(await store.file.readAsString(), bytes);
      await service.renewCredential('a' * 64);
      final renewed = (await store.read())!;
      expect(renewed['recovery_id'], 'original-attempt');
      expect(renewed['prepared_source'], original['prepared_source']);
      expect((renewed['progress'] as Map)['receipt'], {
        'dataset_id': 'published-dataset',
      });
      await expectLater(
        service.reopen(history, '../outside'),
        throwsFormatException,
      );
    },
  );
}
