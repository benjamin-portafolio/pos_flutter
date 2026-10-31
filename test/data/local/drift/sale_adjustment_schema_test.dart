import 'dart:io';
import 'package:pos_flutter/data/local/drift/development_database_reset.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:pos_flutter/data/local/drift/current_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/repositories/sale_adjustment_repository_impl.dart';
import 'package:pos_flutter/domain/ventas/sale_adjustment_status.dart';
import 'package:pos_flutter/application/sync/payloads/sale_adjustment_payload.dart';
import '../../../support/sale_adjustment_harness.dart';

void main() {
  test(
    '2A SQLite temporal: FK, unicidad, rollback, lectura reactiva e idempotencia',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().first;
      await h.seed(f);
      final entry = h.prepare(f);
      final p = SaleAdjustmentPayload.fromJson(entry.event.payload);
      final repo = SaleAdjustmentRepositoryImpl(h.db);
      expect(
        (await repo.watchSales().first).single.status,
        SaleAdjustmentStatus.current,
      );
      var fail = true;
      final events = h.events((e) async {
        await h.store.persistDocument(e, p);
        if (fail) throw StateError('fallo después de líneas');
      });
      await expectLater(
        events.appendAndApply(entry.event, refs: entry.refs),
        throwsStateError,
      );
      expect(await h.db.select(h.db.saleAdjustments).get(), isEmpty);
      expect(await h.db.select(h.db.saleAdjustmentLines).get(), isEmpty);
      expect(await h.db.eventDao.obtenerEventoPorId(p.eventId), isNull);
      fail = false;
      final changed = repo.watchSales().firstWhere(
        (s) => s.single.status == SaleAdjustmentStatus.voided,
      );
      await events.appendAndApply(entry.event, refs: entry.refs);
      expect((await changed).single.original.totalMinor, 1000);
      await h.store.persistDocument(entry.event, p);
      expect((await h.db.select(h.db.saleAdjustments).get()).length, 1);
      expect((await h.db.select(h.db.saleAdjustmentLines).get()).length, 1);
      await expectLater(h.store.dao.insert(entry.event, p), throwsA(anything));
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
      expect(
        (await h.db.eventDao.obtenerEventoPorId(p.eventId))!.deliveryStatus,
        'not_required',
      );
      expect(
        await h.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
  test(
    '2A defensas SQLite: anulación única, revisión única, FK y detección esquema',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().first;
      await h.seed(f);
      final entry = h.prepare(f);
      final p = SaleAdjustmentPayload.fromJson(entry.event.payload);
      await expectLater(
        h.store.persistDocument(entry.event, p),
        throwsA(anything),
      );
      await h
          .events((e) => h.store.persistDocument(e, p))
          .appendAndApply(entry.event, refs: entry.refs);
      final row = (await h.db.select(h.db.saleAdjustments).get()).single;
      final source = (await h.store.confirmation(p.saleId))!;
      final next = row
          .toCompanion(false)
          .copyWith(
            id: const Value('another'),
            eventId: Value(source.eventId),
            revision: const Value(2),
          );
      await expectLater(
        h.db.into(h.db.saleAdjustments).insert(next),
        throwsA(
          predicate((e) => e.toString().contains('sale_adjustments.sale_id')),
        ),
      );
      await expectLater(
        h.db
            .into(h.db.saleAdjustments)
            .insert(
              next.copyWith(
                kind: const Value('return'),
                revision: const Value(1),
              ),
            ),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'sale_adjustments.sale_id, sale_adjustments.revision',
            ),
          ),
        ),
      );
      final line = (await h.db.select(h.db.saleAdjustmentLines).get()).single;
      await expectLater(
        h.db
            .into(h.db.saleAdjustmentLines)
            .insert(
              line
                  .toCompanion(false)
                  .copyWith(saleItemId: const Value('missing')),
            ),
        throwsA(anything),
      );
      final raw = sqlite.sqlite3.open('${h.directory.path}/test.sqlite');
      try {
        expect(hasCurrentAppDatabaseSchema(raw), isTrue);
      } finally {
        raw.close();
      }
      await h.db.customStatement('DROP INDEX ux_sale_void');
      final old = sqlite.sqlite3.open('${h.directory.path}/test.sqlite');
      try {
        expect(hasCurrentAppDatabaseSchema(old), isFalse);
      } finally {
        old.close();
      }
    },
  );
  test(
    '2A reinicio conserva esquema actual y protege respaldo incompatible',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(() async {
        await h.config.dispose();
        await h.directory.delete(recursive: true);
      });
      await h.db.customSelect('SELECT 1 FROM sale_adjustments').get();
      final file = File('${h.directory.path}/test.sqlite');
      await h.db.close();
      expect(
        await resetDevelopmentDatabase(
          file,
          shouldPreserveRestoredDatabase: () async => false,
        ),
        isFalse,
      );
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('DROP INDEX ux_sale_void');
      raw.close();
      await expectLater(
        resetDevelopmentDatabase(
          file,
          shouldPreserveRestoredDatabase: () async => true,
        ),
        throwsStateError,
      );
      expect(await file.exists(), isTrue);
      await expectLater(
        resetDevelopmentDatabase(
          file,
          shouldPreserveRestoredDatabase: () async => false,
        ),
        throwsStateError,
      );
      expect(await file.exists(), isTrue);
    },
  );
}
