import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_json.dart';
import 'package:pos_flutter/application/recovery/recovery_package_reader.dart';
import 'package:pos_flutter/application/recovery/recovery_package_service.dart';
import 'package:pos_flutter/data/local/recovery/sqlite_recovery_snapshot.dart';

String _sourceDigest(String path) {
  final raw = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final content = <String, Object?>{
      for (final t in raw.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ))
        t['name'] as String: raw
            .select('SELECT * FROM "${t['name']}" ORDER BY rowid')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
    };
    expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
    return sha256.convert(utf8.encode(recoveryCanonical(content))).toString();
  } finally {
    raw.close();
  }
}

void main() {
  test(
    'SIGKILL a exportador: origen/paquete válido conservados y regeneración desde corte',
    () async {
      final root = await Directory.systemTemp.createTemp('pos-recovery-crash-');
      addTearDown(() => root.delete(recursive: true));
      final child = await Process.start(
        'flutter',
        [
          'test',
          '--no-pub',
          'test/support/recovery_export_crash_worker.dart',
          '--reporter',
          'expanded',
        ],
        environment: {'POS_RECOVERY_CHILD_DIR': root.path},
      );
      final stdout = child.stdout.transform(utf8.decoder).join();
      final stderr = child.stderr.transform(utf8.decoder).join();
      int? workerPid;
      var commandDone = false;
      child.exitCode.then((_) {
        commandDone = true;
      });
      try {
        final file = File('${root.path}/ready.json');
        final limit = DateTime.now().add(const Duration(seconds: 75));
        while (!file.existsSync() && DateTime.now().isBefore(limit)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(
          file.existsSync(),
          true,
          reason: 'worker no llegó a captura/lote',
        );
        final ready = jsonDecode(await file.readAsString()) as Map;
        workerPid = ready['worker_pid'] as int;
        expect(commandDone, false);
        expect(Process.killPid(workerPid, ProcessSignal.sigkill), true);
        workerPid = null;
        expect(await child.exitCode, isNot(0));
        final errorOutput = await stderr;
        final normalOutput = await stdout;
        expect('$errorOutput$normalOutput', isNotEmpty);
        final s = await SqliteRecoverySnapshot.open(
          File(ready['snapshot'] as String),
        );
        addTearDown(s.close);
        final reader = RecoveryPackageReader();
        final valid = Directory(ready['valid'] as String);
        final digest = await reader.verify(valid, RecoveryCancellation());
        expect(
          _sourceDigest('${root.path}/origin.sqlite'),
          ready['source_digest'],
        );
        final regenerated = await RecoveryPackageService().generate(
          s,
          privateDirectory: Directory('${root.path}/interrupted'),
          cancellation: RecoveryCancellation(),
        );
        expect(
          await reader.verify(regenerated, RecoveryCancellation()),
          digest,
        );
        final orphan = Directory(ready['staging'] as String);
        expect(orphan.parent.path, '${root.path}/interrupted');
        expect(
          orphan.uri.pathSegments.where((s) => s.isNotEmpty).last,
          startsWith('.recovery-${s.cut['package_id']}-'),
        );
        expect(File('${orphan.path}/manifest.json').existsSync(), false);
        // Retirada explícita de la ejecución conocida y ya terminada; nunca barrido.
        await orphan.delete(recursive: true);
        expect(await reader.verify(valid, RecoveryCancellation()), digest);
        expect(
          await reader.verify(regenerated, RecoveryCancellation()),
          digest,
        );
      } finally {
        if (!commandDone && workerPid != null) {
          Process.killPid(workerPid, ProcessSignal.sigkill);
        }
        if (!commandDone) child.kill(ProcessSignal.sigterm);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
