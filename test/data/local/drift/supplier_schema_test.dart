import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p', name: 'Café'));
    for (var i = 1; i <= 2; i++) {
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: 'v$i',
              productId: 'p',
              salePriceMinor: 2500,
              standardCostMinor: const Value(1500),
              sortOrder: i - 1,
            ),
          );
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              id: 's$i',
              name: 'Mismo nombre',
              createdEventId: Value('e$i'),
              lastEventId: Value('e$i'),
            ),
          );
    }
  });
  tearDown(() => db.close());
  Future<void> relation({
    String v = 'v1',
    String s = 's1',
    Object? price = 0,
    Object? at = 1,
  }) => db.customStatement(
    'INSERT INTO variant_suppliers(variant_id,supplier_id,quoted_price_minor,quoted_at_ms) VALUES(?,?,?,?)',
    [v, s, price, at],
  );
  final constraintError = throwsA(isA<sqlite.SqliteException>());

  test(
    'CommonFields, nombres repetidos, varias relaciones y mismo proveedor en dos variantes',
    () async {
      await relation();
      await relation(s: 's2', price: 9007199254740991, at: 9007199254740991);
      await relation(v: 'v2');
      final suppliers = await db.select(db.suppliers).get();
      expect(suppliers, hasLength(2));
      expect(suppliers.first.active, isTrue);
      expect(suppliers.first.version, 1);
      expect(suppliers.first.createdEventId, 'e1');
      expect(suppliers.first.phone, isNull);
      expect(suppliers.first.notes, isNull);
      expect(await db.select(db.variantSuppliers).get(), hasLength(3));
      final columns = (await db
          .customSelect('PRAGMA table_info(variant_suppliers)')
          .get());
      expect(columns.map((c) => c.data['name']), [
        'variant_id',
        'supplier_id',
        'quoted_price_minor',
        'quoted_at_ms',
      ]);
      expect(
        columns
            .where((c) => (c.data['pk'] as int) > 0)
            .map((c) => c.data['name']),
        ['variant_id', 'supplier_id'],
      );
      final variant = (await db.select(db.productVariants).get()).first;
      expect(variant.salePriceMinor, 2500);
      expect(variant.standardCostMinor, 1500);
      expect(await db.select(db.inventoryMovements).get(), isEmpty);
      expect(db.schemaVersion, 8);
    },
  );
  test('nombre requerido sin unicidad global', () async {
    for (final name in ['', '  ', '\t\n\r']) {
      await expectLater(
        db
            .into(db.suppliers)
            .insert(SuppliersCompanion.insert(id: 'bad', name: name)),
        constraintError,
      );
    }
  });
  test('clave compuesta no repite proveedor por variante', () async {
    await relation();
    await expectLater(relation(price: 99), constraintError);
    expect(await db.select(db.variantSuppliers).get(), hasLength(1));
  });
  for (final price in <Object?>[null, '', -1, 9007199254740992, 1.5]) {
    test(
      'precio SQLite inválido $price',
      () async => expectLater(relation(price: price), constraintError),
    );
  }
  for (final at in <Object?>[null, '', 0, -1, 9007199254740992, 1.5]) {
    test(
      'fecha SQLite inválida $at',
      () async => expectLater(relation(at: at), constraintError),
    );
  }
  test('FK rechaza variante/proveedor inexistentes', () async {
    await expectLater(relation(v: 'unknown'), constraintError);
    await expectLater(relation(s: 'unknown'), constraintError);
    expect(await db.select(db.variantSuppliers).get(), isEmpty);
  });
  test(
    'RESTRICT proveedor y CASCADE variante conservan catálogo y otros precios',
    () async {
      await relation();
      await relation(v: 'v2');
      await expectLater(
        (db.delete(db.suppliers)..where((s) => s.id.equals('s1'))).go(),
        constraintError,
      );
      await (db.delete(
        db.productVariants,
      )..where((v) => v.id.equals('v1'))).go();
      expect(
        (await db.select(db.variantSuppliers).get()).single.variantId,
        'v2',
      );
      await (db.delete(db.products)..where((p) => p.id.equals('p'))).go();
      expect(await db.select(db.variantSuppliers).get(), isEmpty);
      expect(await db.select(db.suppliers).get(), hasLength(2));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
  test('retirar última relación no elimina proveedor', () async {
    await relation();
    await db.delete(db.variantSuppliers).go();
    expect(await db.select(db.variantSuppliers).get(), isEmpty);
    expect(await db.select(db.suppliers).get(), hasLength(2));
  });
}
