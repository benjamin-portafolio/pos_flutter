import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'dart:convert';
import 'tables/product_update_undo.dart';
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
part 'daos/producto_listado_row.dart';
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
    ProductUpdateUndo,
    RecipeComponents,
    Espacios,
    Events,
    EventRefs,
    SyncCheckpoints,
    Units,
    InventoryItems,
    InventoryBalances,
    InventoryMovements,
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
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedInventoryUnits();
    },
    onUpgrade: (m, from, to) async {
      if (from < 4) {
        await m.createTable(units);
        await _seedInventoryUnits();
        await m.createTable(inventoryItems);
        await m.createTable(inventoryBalances);
        await m.createTable(inventoryMovements);
      }
      if (from < 5) {
        await m.addColumn(products, products.saleMode);
        await m.addColumn(products, products.saleUnitId);
        await m.addColumn(products, products.priceReferenceQuantityAtomic);
      }
      if (from < 6) {
        await customStatement('DROP TABLE IF EXISTS recipe_components');
        await m.alterTable(TableMigration(products));
        await m.alterTable(TableMigration(productVariants));
        await m.alterTable(TableMigration(inventoryMovements));
      }
      if (from >= 4 && from < 7) {
        await m.addColumn(inventoryBalances, inventoryBalances.version);
        await m.alterTable(TableMigration(inventoryMovements));
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
    await _resetDatabaseOnStartup(file);

    return NativeDatabase.createInBackground(file);
  });
}

/// Durante desarrollo se recrea una base anterior a este esquema, sin migrar
/// ni cambiar schemaVersion. La columna legada is_default identifica bases
/// anteriores; las bases actuales se conservan entre arranques.
Future<void> _resetDatabaseOnStartup(File file) async {
  if (!await file.exists()) return;
  final connection = sqlite.sqlite3.open(file.path);
  final bool current;
  try {
    final variantColumns = connection.select(
      'PRAGMA table_info(product_variants)',
    );
    current =
        connection
            .select(
              "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'product_update_undo'",
            )
            .isNotEmpty &&
        variantColumns.isNotEmpty &&
        !variantColumns.any((column) => column['name'] == 'is_default');
  } finally {
    connection.close();
  }
  if (current) return;
  if (await appDatabaseShouldPreserveRestoredDatabase()) {
    throw StateError(
      'El respaldo restaurado usa un esquema anterior. Se requiere una base del esquema actual.',
    );
  }
  for (final suffix in ['', '-wal', '-shm']) {
    final old = File('${file.path}$suffix');
    if (await old.exists()) await old.delete();
  }
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
