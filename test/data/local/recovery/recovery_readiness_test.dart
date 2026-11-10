import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_readiness_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_snapshot_source.dart';
import '../../../support/product_supplier_harness.dart';

void main() {
  for (final mode in AppMode.values) {
    test(
      'preparación $mode conserva todas las tablas y diagnóstico al reabrir',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'pos-recovery-s5-test-',
        );
        final h = ProductSupplierHarness(
          mode: mode,
          database: AppDatabase.forTesting(
            NativeDatabase(File('${dir.path}/origin.sqlite')),
          ),
        );
        try {
          await h.supplier('Origen preservado');
          Future<Map<String, Object?>> rows() async {
            final tables = await h.db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
                )
                .get();
            return {
              for (final t in tables)
                t.data['name'] as String:
                    (await h.db
                            .customSelect(
                              'SELECT * FROM "${t.data['name']}" ORDER BY rowid',
                            )
                            .get())
                        .map((r) => r.data)
                        .toList(),
            };
          }

          final before = jsonEncode(await rows());
          final service = RecoveryReadinessService(
            source: DriftRecoverySnapshotSource(h.db),
            privateDirectory: () async => Directory('${dir.path}/private'),
            deviceId: 'fixture-device',
            appRevision: 'fixture-s5',
          );
          final report = await service.diagnose(mode, RecoveryCancellation());
          final d = report['diagnostic'] as Map;
          expect(d['admissible'], false);
          final codes = (d['blockers'] as List).map((r) => (r as Map)['code']);
          expect(
            codes,
            contains(
              mode == AppMode.standalone
                  ? 'standalone_not_supported'
                  : 'pending',
            ),
          );
          final snapshot = File(report['snapshot_path'] as String);
          expect(await snapshot.exists(), true);
          final durable = jsonDecode(
            await File(
              '${snapshot.parent.path}/diagnostic.json',
            ).readAsString(),
          );
          expect(durable, d);
          expect(await File('${snapshot.parent.path}/cut.json').exists(), true);
          expect(jsonEncode(await rows()), before);
          expect(await Directory('${dir.path}/private').list().length, 1);
        } finally {
          await h.dispose();
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
