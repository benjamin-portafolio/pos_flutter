import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/offer_pricing_schema.dart';
import 'package:pos_flutter/data/local/drift/current_database_schema.dart';
import 'package:sqlite3/sqlite3.dart';
import '../drift/offer_pricing_migration_test.dart' as legacy;

void main() {
  for (final mode in ['not_required', 'pending']) {
    test(
      'v9 reconocida -> v10 conserva todas las filas ($mode), revisión transaccional',
      () async {
        final dir = await Directory.systemTemp.createTemp('recovery-v9-');
        addTearDown(() => dir.delete(recursive: true));
        final f = File('${dir.path}/origin.sqlite');
        legacy.seedV8(f);
        final db = sqlite3.open(f.path);
        for (final table in offerPricingColumns.entries) {
          for (final col in table.value.entries) {
            db.execute(
              'ALTER TABLE ${table.key} ADD COLUMN ${col.key} ${col.value}',
            );
          }
        }
        for (final ddl in offerPricingTriggers) {
          db.execute(ddl);
        }
        db.execute('PRAGMA user_version=9');
        db.execute('UPDATE events SET delivery_status=?', [mode]);
        expect(hasRecognizedOfferSchema(db), true);
        db.close();
        final before = legacy.snapshot(f);
        await prepareAppDatabase(f);
        final after = legacy.snapshot(f);
        for (final t in before.keys) {
          expect(after[t], before[t], reason: t);
        }
        final current = sqlite3.open(f.path);
        expect(hasCurrentAppDatabaseSchema(current), true);
        final revision = current
            .select('SELECT data_revision FROM recovery_local_state')
            .single['data_revision'];
        expect(revision, 0);
        current.execute('BEGIN');
        current.execute("UPDATE products SET name='Un cambio'");
        current.execute('ROLLBACK');
        expect(
          current
              .select('SELECT data_revision FROM recovery_local_state')
              .single['data_revision'],
          revision,
        );
        current.execute("UPDATE events SET rejection_reason='fixture'");
        expect(
          current
              .select('SELECT data_revision FROM recovery_local_state')
              .single['data_revision'],
          1,
        );
        expect(
          current
              .select('SELECT delivery_status FROM events')
              .single['delivery_status'],
          mode,
        );
        current.close();
        await prepareAppDatabase(f);
      },
    );
  }
}
