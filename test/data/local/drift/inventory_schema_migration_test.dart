import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  test(
    'migra schema 4 a 7 y elimina campos de inventario del artículo',
    () async {
      final directory = await Directory.systemTemp.createTemp('pos-schema-v4-');
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
      await current.customStatement(
        'ALTER TABLE inventory_balances DROP COLUMN version',
      );
      await current.customStatement('''
      CREATE TABLE products_v4 AS
      SELECT id, active, version, created_event_id, last_event_id,
        last_server_sequence, name, category_id, 'direct' AS inventory_mode
      FROM products
    ''');
      await current.customStatement('DROP TABLE products');
      await current.customStatement(
        'ALTER TABLE products_v4 RENAME TO products',
      );
      await current.customStatement('PRAGMA user_version = 4');
      await current.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(migrated.close);
      final product = await (migrated.select(
        migrated.products,
      )..where((row) => row.id.equals('product-legacy'))).getSingle();
      expect(product.name, 'Producto legado');
      expect(product.saleMode, 'unit');
      expect(product.saleUnitId, isA<Null>());
      expect(product.priceReferenceQuantityAtomic, isA<Null>());
      final variantColumns = await migrated
          .customSelect('PRAGMA table_info(product_variants)')
          .get();
      final variantColumnNames = variantColumns.map(
        (row) => row.read<String>('name'),
      );
      expect(variantColumnNames, isNot(contains('inventory_behavior')));
      expect(variantColumnNames, isNot(contains('inventory_enabled')));
      expect(variantColumnNames, isNot(contains('direct_inventory_item_id')));
      expect(variantColumnNames, isNot(contains('direct_quantity_atomic')));
      expect(await migrated.select(migrated.inventoryItems).get(), isEmpty);
      expect(await migrated.select(migrated.units).get(), hasLength(5));
      final versionRow = await migrated
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(versionRow.read<int>('user_version'), 7);
    },
  );

  test(
    'migra schema 5 a 7 y permite varios movimientos del mismo evento',
    () async {
      final directory = await Directory.systemTemp.createTemp('pos-schema-v5-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/migration.sqlite');

      final current = AppDatabase.forTesting(NativeDatabase(file));
      await current
          .into(current.inventoryItems)
          .insert(
            InventoryItemsCompanion.insert(
              id: 'inventory-item',
              name: 'Insumo',
              defaultUnitId: '10000000-0000-4000-8000-000000000001',
              createdEventId: const Value('event-resource'),
              lastEventId: const Value('event-resource'),
            ),
          );
      await current.customStatement('PRAGMA foreign_keys = OFF');
      await current.customStatement(
        'ALTER TABLE inventory_balances DROP COLUMN version',
      );
      await current.customStatement(
        "ALTER TABLE products ADD COLUMN inventory_mode TEXT NOT NULL DEFAULT 'direct'",
      );
      await current.customStatement(
        "ALTER TABLE product_variants ADD COLUMN inventory_behavior TEXT NOT NULL DEFAULT 'none'",
      );
      await current.customStatement('''
        CREATE TABLE recipe_components (
          variant_id TEXT NOT NULL,
          inventory_item_id TEXT NOT NULL,
          quantity_atomic INTEGER NOT NULL
        )
      ''');
      await current.customStatement('''
        CREATE TABLE inventory_movements_v5 (
          movement_id TEXT NOT NULL PRIMARY KEY,
          inventory_item_id TEXT NOT NULL,
          sale_item_id TEXT,
          event_id TEXT NOT NULL UNIQUE,
          reversal_of_movement_id TEXT,
          movement_type TEXT NOT NULL,
          quantity_delta_atomic INTEGER NOT NULL
            CHECK (quantity_delta_atomic <> 0),
          total_cost_minor INTEGER,
          reason TEXT NOT NULL,
          created_at_local INTEGER NOT NULL,
          server_sequence INTEGER
        )
      ''');
      await current.customStatement('DROP TABLE inventory_movements');
      await current.customStatement(
        'ALTER TABLE inventory_movements_v5 RENAME TO inventory_movements',
      );
      await current.customStatement('PRAGMA user_version = 5');
      await current.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(migrated.close);
      await migrated
          .into(migrated.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              movementId: 'movement-1',
              inventoryItemId: 'inventory-item',
              eventId: 'event-sale',
              movementType: 'sale_consumption',
              quantityDeltaAtomic: -1,
              reason: const Value('Componente 1'),
              createdAtLocal: DateTime.utc(2026, 8, 21),
            ),
          );
      await migrated
          .into(migrated.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              movementId: 'movement-2',
              inventoryItemId: 'inventory-item',
              eventId: 'event-sale',
              movementType: 'sale_consumption',
              quantityDeltaAtomic: -2,
              reason: const Value('Componente 2'),
              createdAtLocal: DateTime.utc(2026, 8, 21),
            ),
          );

      final productColumns = await migrated
          .customSelect('PRAGMA table_info(products)')
          .get();
      final variantColumns = await migrated
          .customSelect('PRAGMA table_info(product_variants)')
          .get();
      expect(
        productColumns.map((row) => row.read<String>('name')),
        isNot(contains('inventory_mode')),
      );
      expect(
        variantColumns.map((row) => row.read<String>('name')),
        isNot(contains('inventory_behavior')),
      );
      final removedRecipeTable = await migrated.customSelect('''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name = 'recipe_components'
      ''').get();
      expect(removedRecipeTable, isEmpty);
      expect(
        await migrated.select(migrated.inventoryMovements).get(),
        hasLength(2),
      );
      final versionRow = await migrated
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(versionRow.read<int>('user_version'), 7);
    },
  );

  test(
    'migra schema 6 a 7, conserva historial y permite reason null',
    () async {
      final directory = await Directory.systemTemp.createTemp('pos-schema-v6-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/migration.sqlite');

      final current = AppDatabase.forTesting(NativeDatabase(file));
      await current
          .into(current.inventoryItems)
          .insert(
            InventoryItemsCompanion.insert(
              id: 'inventory-item',
              name: 'Insumo',
              defaultUnitId: '10000000-0000-4000-8000-000000000001',
              createdEventId: const Value('event-resource'),
              lastEventId: const Value('event-resource'),
            ),
          );
      await current.customStatement('PRAGMA foreign_keys = OFF');
      await current.customStatement(
        'ALTER TABLE inventory_balances DROP COLUMN version',
      );
      await current.customStatement('DROP TABLE inventory_movements');
      await current.customStatement('''
      CREATE TABLE inventory_movements (
        movement_id TEXT NOT NULL PRIMARY KEY,
        inventory_item_id TEXT NOT NULL,
        sale_item_id TEXT,
        event_id TEXT NOT NULL,
        reversal_of_movement_id TEXT,
        movement_type TEXT NOT NULL,
        quantity_delta_atomic INTEGER NOT NULL
          CHECK (quantity_delta_atomic <> 0),
        total_cost_minor INTEGER,
        reason TEXT NOT NULL,
        created_at_local INTEGER NOT NULL,
        server_sequence INTEGER
      )
    ''');
      await current.customStatement('''
      INSERT INTO inventory_movements (
        movement_id, inventory_item_id, event_id, movement_type,
        quantity_delta_atomic, total_cost_minor, reason, created_at_local
      ) VALUES (
        'legacy-movement', 'inventory-item', 'legacy-event',
        'manual_adjustment', -2, NULL, 'Conteo histórico', 0
      )
    ''');
      await current.customStatement('PRAGMA user_version = 6');
      await current.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(migrated.close);
      final legacy = await (migrated.select(
        migrated.inventoryMovements,
      )..where((row) => row.movementId.equals('legacy-movement'))).getSingle();
      expect(legacy.reason, 'Conteo histórico');
      expect(legacy.reversalOfMovementId, isA<Null>());
      expect(legacy.totalCostMinor, isA<Null>());

      await migrated
          .into(migrated.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              movementId: 'receipt-movement',
              inventoryItemId: 'inventory-item',
              eventId: 'receipt-event',
              movementType: 'stock_receipt',
              quantityDeltaAtomic: 5,
              createdAtLocal: DateTime.utc(2026, 8, 29),
            ),
          );
      final receipt = await (migrated.select(
        migrated.inventoryMovements,
      )..where((row) => row.movementId.equals('receipt-movement'))).getSingle();
      expect(receipt.reason, isA<Null>());
      expect(
        () => migrated
            .into(migrated.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                movementId: 'untrimmed-receipt',
                inventoryItemId: 'inventory-item',
                eventId: 'untrimmed-event',
                movementType: 'stock_receipt',
                quantityDeltaAtomic: 1,
                reason: const Value(' Compra '),
                createdAtLocal: DateTime.utc(2026, 8, 29),
              ),
            ),
        throwsA(isA<Exception>()),
      );
      expect(
        () => migrated
            .into(migrated.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                movementId: 'invalid-manual',
                inventoryItemId: 'inventory-item',
                eventId: 'invalid-event',
                movementType: 'manual_adjustment',
                quantityDeltaAtomic: 1,
                createdAtLocal: DateTime.utc(2026, 8, 29),
              ),
            ),
        throwsA(isA<Exception>()),
      );
      final balanceColumns = await migrated
          .customSelect('PRAGMA table_info(inventory_balances)')
          .get();
      expect(
        balanceColumns.map((row) => row.read<String>('name')),
        contains('version'),
      );
      final versionRow = await migrated
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(versionRow.read<int>('user_version'), 7);
    },
  );
}
