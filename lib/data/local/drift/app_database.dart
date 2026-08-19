import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pos_flutter/data/local/drift/tables/categories.dart';
import 'package:pos_flutter/data/local/drift/tables/espacios.dart';
import 'package:pos_flutter/data/local/drift/tables/events.dart';
import 'package:pos_flutter/data/local/drift/tables/event_refs.dart';
import 'package:pos_flutter/data/local/drift/tables/inventory_balances.dart';
import 'package:pos_flutter/data/local/drift/tables/inventory_items.dart';
import 'package:pos_flutter/data/local/drift/tables/inventory_movements.dart';
import 'package:pos_flutter/data/local/drift/tables/product_variants.dart';
import 'package:pos_flutter/data/local/drift/tables/products.dart';
import 'package:pos_flutter/data/local/drift/tables/recipe_components.dart';
import 'package:pos_flutter/data/local/drift/tables/sync_checkpoints.dart';
import 'package:pos_flutter/data/local/drift/tables/units.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

part 'app_database.g.dart';
part 'daos/categoria_dao.dart';
part 'daos/espacio_dao.dart';
part 'daos/event_dao.dart';
part 'daos/event_ref_dao.dart';
part 'daos/inventory_dao.dart';
part 'daos/producto_dao.dart';
part 'daos/sync_checkpoint_dao.dart';
part 'daos/unit_dao.dart';

const _databaseFileName = 'pos_db.sqlite';
const _preserveRestoredDatabaseFileName = '.pos_db_restored';

/// Database class configuring connection, schema and registered tables/DAOs.
@DriftDatabase(
  tables: [
    Categories,
    Products,
    ProductVariants,
    Espacios,
    Events,
    EventRefs,
    SyncCheckpoints,
    Units,
    InventoryItems,
    InventoryBalances,
    InventoryMovements,
    RecipeComponents,
  ],
  daos: [
    CategoriaDao,
    ProductoDao,
    EspacioDao,
    EventDao,
    EventRefDao,
    SyncCheckpointDao,
    UnitDao,
    InventoryDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedInventoryUnits();
    },
    onUpgrade: (m, from, to) async {
      if (from < 4) {
        await m.addColumn(products, products.inventoryMode);
        await m.createTable(units);
        await _seedInventoryUnits();
        await m.createTable(inventoryItems);
        await m.addColumn(productVariants, productVariants.inventoryEnabled);
        await m.addColumn(
          productVariants,
          productVariants.directInventoryItemId,
        );
        await m.addColumn(
          productVariants,
          productVariants.directQuantityAtomic,
        );
        await customStatement('''
          UPDATE product_variants
          SET inventory_enabled = CASE
            WHEN inventory_behavior = 'none' THEN 0
            ELSE inventory_enabled
          END
        ''');
        await m.createTable(inventoryBalances);
        await m.createTable(inventoryMovements);
        await m.createTable(recipeComponents);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seedInventoryUnits() async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(units, [
        UnitsCompanion.insert(
          unitId: InventoryUnitIds.piece,
          code: 'piece',
          name: 'Pieza',
          symbol: 'pza',
          dimension: 'count',
          atomicFactor: 1,
          maxFractionDigits: 0,
        ),
        UnitsCompanion.insert(
          unitId: InventoryUnitIds.gram,
          code: 'g',
          name: 'Gramo',
          symbol: 'g',
          dimension: 'mass',
          atomicFactor: 1,
          maxFractionDigits: 0,
        ),
        UnitsCompanion.insert(
          unitId: InventoryUnitIds.kilogram,
          code: 'kg',
          name: 'Kilogramo',
          symbol: 'kg',
          dimension: 'mass',
          atomicFactor: 1000,
          maxFractionDigits: 3,
        ),
        UnitsCompanion.insert(
          unitId: InventoryUnitIds.milliliter,
          code: 'ml',
          name: 'Mililitro',
          symbol: 'ml',
          dimension: 'volume',
          atomicFactor: 1,
          maxFractionDigits: 0,
        ),
        UnitsCompanion.insert(
          unitId: InventoryUnitIds.liter,
          code: 'l',
          name: 'Litro',
          symbol: 'L',
          dimension: 'volume',
          atomicFactor: 1000,
          maxFractionDigits: 3,
        ),
      ]);
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await appDatabaseFile();

    return NativeDatabase.createInBackground(file);
  });
}

Future<File> appDatabaseFile() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return File(p.join(dbFolder.path, _databaseFileName));
}

Future<File> appDatabaseRestorePreservationFile() async {
  final databaseFile = await appDatabaseFile();
  return File(
    p.join(databaseFile.parent.path, _preserveRestoredDatabaseFileName),
  );
}

Future<bool> appDatabaseShouldPreserveRestoredDatabase() async {
  final file = await appDatabaseRestorePreservationFile();
  return file.exists();
}

Future<void> markAppDatabaseAsRestored() async {
  final file = await appDatabaseRestorePreservationFile();
  await file.writeAsString(
    DateTime.now().toUtc().toIso8601String(),
    flush: true,
  );
}
