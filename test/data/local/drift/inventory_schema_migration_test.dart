import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  test('migra schema 3 a 4 y conserva productos sin crear recursos', () async {
    final directory = await Directory.systemTemp.createTemp('pos-schema-v3-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/migration.sqlite');

    final current = AppDatabase.forTesting(NativeDatabase(file));
    await current
        .into(current.products)
        .insert(
          ProductsCompanion.insert(
            id: 'product-legacy',
            name: 'Producto legado',
            createdEventId: const Value('event-legacy'),
            lastEventId: const Value('event-legacy'),
          ),
        );
    await current
        .into(current.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: 'variant-legacy',
            productId: 'product-legacy',
            salePriceMinor: 1000,
            isDefault: true,
            sortOrder: 0,
            createdEventId: const Value('event-legacy'),
            lastEventId: const Value('event-legacy'),
          ),
        );
    await current.customStatement('PRAGMA foreign_keys = OFF');
    await current.customStatement('DROP TABLE recipe_components');
    await current.customStatement('DROP TABLE inventory_movements');
    await current.customStatement('DROP TABLE inventory_balances');
    await current.customStatement(
      'ALTER TABLE product_variants DROP COLUMN direct_quantity_atomic',
    );
    await current.customStatement(
      'ALTER TABLE product_variants DROP COLUMN direct_inventory_item_id',
    );
    await current.customStatement(
      'ALTER TABLE product_variants DROP COLUMN inventory_enabled',
    );
    await current.customStatement('DROP TABLE inventory_items');
    await current.customStatement('DROP TABLE units');
    await current.customStatement(
      'ALTER TABLE products DROP COLUMN inventory_mode',
    );
    await current.customStatement('PRAGMA user_version = 3');
    await current.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(migrated.close);
    final product = await (migrated.select(
      migrated.products,
    )..where((row) => row.id.equals('product-legacy'))).getSingle();
    final variant = await (migrated.select(
      migrated.productVariants,
    )..where((row) => row.id.equals('variant-legacy'))).getSingle();

    expect(product.name, 'Producto legado');
    expect(product.inventoryMode, 'direct');
    expect(variant.inventoryBehavior, 'none');
    expect(variant.inventoryEnabled, isFalse);
    expect(variant.directInventoryItemId, isA<Null>());
    expect(await migrated.select(migrated.inventoryItems).get(), isEmpty);
    expect(await migrated.select(migrated.units).get(), hasLength(5));
    final versionRow = await migrated
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(versionRow.read<int>('user_version'), 4);
  });
}
