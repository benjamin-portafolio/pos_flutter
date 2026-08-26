import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'product', name: 'Producto'));
  });

  tearDown(() => db.close());

  test('permite varias variantes sin nombre y costo cero', () async {
    await _insertVariant(db, id: 'v1', order: 0, isDefault: true, cost: 0);
    await _insertVariant(db, id: 'v2', order: 1, isDefault: false);
    expect(await db.select(db.productVariants).get(), hasLength(2));
  });

  test('impone coherencia, importes, orden y nombre único', () async {
    await _insertVariant(
      db,
      id: 'v1',
      order: 0,
      isDefault: true,
      name: 'Grande',
      nameKey: 'grande',
    );

    await expectLater(
      _insertVariant(
        db,
        id: 'bad-name',
        order: 1,
        isDefault: false,
        name: 'Sin clave',
      ),
      throwsA(anything),
    );
    await expectLater(
      _insertVariant(
        db,
        id: 'bad-price',
        order: 1,
        isDefault: false,
        price: 0,
      ),
      throwsA(anything),
    );
    await expectLater(
      _insertVariant(
        db,
        id: 'bad-cost',
        order: 1,
        isDefault: false,
        cost: -1,
      ),
      throwsA(anything),
    );
    await expectLater(
      _insertVariant(
        db,
        id: 'bad-order',
        order: -1,
        isDefault: false,
      ),
      throwsA(anything),
    );
    await expectLater(
      _insertVariant(
        db,
        id: 'duplicate-name',
        order: 1,
        isDefault: false,
        name: 'GRANDE',
        nameKey: 'grande',
      ),
      throwsA(anything),
    );
  });
}

Future<void> _insertVariant(
  AppDatabase db, {
  required String id,
  required int order,
  required bool isDefault,
  String? name,
  String? nameKey,
  int price = 100,
  int? cost,
}) {
  return db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: id,
          productId: 'product',
          name: Value(name),
          nameKey: Value(nameKey),
          salePriceMinor: price,
          standardCostMinor: Value(cost),
          isDefault: isDefault,
          sortOrder: order,
        ),
      );
}
