import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_json.dart';
import 'package:pos_flutter/application/recovery/recovery_package_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_snapshot_source.dart';
import 'product_supplier_harness.dart';

// Solo lo invoca recovery_interruption_test sobre un directorio temporal nuevo.
void main() {
  test('export worker isolated', () async {
    final root = Platform.environment['POS_RECOVERY_CHILD_DIR'];
    if (root == null || !Directory(root).existsSync()) {
      throw StateError('Falta fixture aislado.');
    }
    final h = ProductSupplierHarness(
      database: AppDatabase.forTesting(
        NativeDatabase(File('$root/origin.sqlite')),
      ),
      mode: AppMode.serverSync,
    );
    await h.db.customStatement('PRAGMA journal_mode=WAL');
    await h.db.customStatement('PRAGMA wal_autocheckpoint=0');
    await h.supplier('Fixture de interrupción');
    await h.db.customStatement(
      "UPDATE events SET delivery_status='delivered',server_sequence=7,created_at_server=1794153600",
    );
    await h.db.customStatement(
      "INSERT INTO sync_checkpoints(checkpoint_id,last_full_pull_server_sequence,last_full_pull_at) VALUES ('full_pull',7,1794153600)",
    );
    final before = <String, Object?>{
      for (final t in h.db.allTables)
        t.actualTableName:
            (await h.db
                    .customSelect(
                      'SELECT * FROM "${t.actualTableName}" ORDER BY rowid',
                    )
                    .get())
                .map((r) => r.data)
                .toList(),
    };
    final s = await DriftRecoverySnapshotSource(h.db).capture(
      privateDirectory: Directory('$root/captures'),
      mode: AppMode.serverSync,
      deviceId: 'crash-fixture',
      appRevision: 's3-test',
      cancellation: RecoveryCancellation(),
    );
    final service = RecoveryPackageService();
    final valid = await service.generate(
      s,
      privateDirectory: Directory('$root/valid'),
      cancellation: RecoveryCancellation(),
    );
    await service.generate(
      s,
      privateDirectory: Directory('$root/interrupted'),
      cancellation: RecoveryCancellation(),
      writeFile: (file, bytes) async {
        await file.writeAsBytes(bytes.take(5).toList(), flush: true);
        await File('$root/ready.json').writeAsString(
          jsonEncode({
            'worker_pid': pid,
            'staging': file.parent.path,
            'snapshot': s.file.path,
            'valid': valid.path,
            'source_digest': sha256
                .convert(utf8.encode(recoveryCanonical(before)))
                .toString(),
          }),
          flush: true,
        );
        await Completer<void>().future;
      },
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
