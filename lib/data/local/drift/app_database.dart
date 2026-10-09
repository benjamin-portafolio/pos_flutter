import 'tables/suppliers.dart';
import 'tables/variant_suppliers.dart';
import 'current_database_schema.dart';
import '../../../domain/inventario/inventory_consumption_configuration.dart';
import 'tables/credit_sales.dart';
import 'tables/customer_payments.dart';
import 'tables/credit_allocations.dart';
import 'tables/clientes.dart';
import 'tables/financial_categories.dart';
import 'tables/financial_entries.dart';
import 'tables/cash_sessions.dart';
import 'tables/cash_movements.dart';
import 'tables/account_balance_baselines.dart';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pos_flutter/data/local/drift/tables/categories.dart';
import 'package:pos_flutter/data/local/drift/tables/espacios.dart';
import 'package:pos_flutter/data/local/drift/tables/event_refs.dart';
import 'package:pos_flutter/data/local/drift/tables/events.dart';
import 'package:pos_flutter/data/local/drift/tables/inventory_balances.dart';
import 'package:pos_flutter/data/local/drift/tables/inventory_item_discards.dart';
import 'package:pos_flutter/data/local/drift/tables/inventory_items.dart';
import 'package:pos_flutter/data/local/drift/tables/inventory_movements.dart';
import 'package:pos_flutter/data/local/drift/tables/product_variants.dart';
import 'package:pos_flutter/data/local/drift/tables/products.dart';
import 'package:pos_flutter/data/local/drift/tables/recipe_components.dart';
import 'package:pos_flutter/data/local/drift/tables/sync_checkpoints.dart';
import 'package:pos_flutter/data/local/drift/tables/units.dart';
import 'package:pos_flutter/data/local/drift/tables/variant_inventory_memory.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../application/sync/payloads/sale_item_snapshot.dart';
import '../../../application/sync/payloads/venta_confirmada_payload.dart';
import '../../../application/sync/payloads/venta_borrador_limpiada_payload.dart';
import '../../../application/sync/projections/sale_draft_projection_store.dart';
import '../../../application/sync/projections/sale_item_projection.dart';
import '../../../application/sync/projections/sale_projection.dart';
import '../../../domain/ventas/sale_status.dart';
import 'tables/product_update_undo.dart';
import 'tables/sale_items.dart';
import 'tables/sales.dart';
import 'tables/sale_payments.dart';
import 'tables/quotations.dart';
import 'tables/quotation_items.dart';
import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/projections/quotation_projection_store.dart';
import '../../../application/sync/projections/quotation_projection.dart';
import '../../../application/sync/projections/quotation_item_projection.dart';
import '../../../application/sync/payloads/quotation_selection_snapshot.dart';

part 'app_database.g.dart';
part 'daos/cliente_dao.dart';
part 'daos/proveedor_dao.dart';
part 'daos/sale_dao.dart';
part 'daos/quotation_dao.dart';
part 'daos/categoria_dao.dart';
part 'daos/espacio_dao.dart';
part 'daos/event_dao.dart';
part 'daos/event_ref_dao.dart';
part 'daos/financial_category_dao.dart';
part 'daos/financial_entry_dao.dart';
part 'daos/inventory_dao.dart';
part 'daos/producto_dao.dart';
part 'daos/producto_codigo_barras_row.dart';
part 'daos/producto_listado_row.dart';
part 'daos/sync_checkpoint_dao.dart';
part 'daos/unit_dao.dart';
part 'daos/variant_inventory_memory_dao.dart';

const _databaseFileName = 'pos_db.sqlite';
const _preserveRestoredDatabaseFileName = '.pos_db_restored';

/// Database class configuring connection, schema and registered tables/DAOs.
@DriftDatabase(
  tables: [
    Clientes,
    Categories,
    Products,
    ProductVariants,
    ProductUpdateUndo,
    RecipeComponents,
    Suppliers,
    VariantSuppliers,
    Espacios,
    Events,
    EventRefs,
    SyncCheckpoints,
    Units,
    InventoryItems,
    InventoryBalances,
    InventoryMovements,
    VariantInventoryMemory,
    InventoryItemDiscards,
    Sales,
    SaleItems,
    SalePayments,
    Quotations,
    QuotationItems,
    CreditSales,
    CustomerPayments,
    CreditAllocations,
    FinancialCategories,
    FinancialEntries,
    CashSessions,
    CashMovements,
    AccountBalanceBaselines,
  ],
  daos: [
    ClienteDao,
    ProveedorDao,
    CategoriaDao,
    ProductoDao,
    EspacioDao,
    EventDao,
    EventRefDao,
    SyncCheckpointDao,
    UnitDao,
    InventoryDao,
    SaleDao,
    QuotationDao,
    FinancialCategoryDao,
    FinancialEntryDao,
    VariantInventoryMemoryDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

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
      // Bloque propio y no dentro del `from < 7` de arriba: ese rango excluye
      // el esquema 7, y una base en 7 tiene que pasar por aquí.
      if (from < 8) {
        await m.createTable(accountBalanceBaselines);
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
/// ni cambiar schemaVersion. Las tablas de crédito y clientes deben existir,
/// sales debe incluir cliente_id, product_variants debe incluir barcode, no
/// puede conservarse la columna legada is_default y el módulo de
/// ingresos/gastos requiere financial_categories y financial_entries; el
/// seguimiento de existencias requiere inventory_items.origin_variant_id y las
/// tablas variant_inventory_memory e inventory_item_discards; las bases
/// actuales se conservan entre arranques. Cotizaciones requiere quotations,
/// quotation_items sin condiciones monetarias y sus índices. Una base previa
/// o con columnas retiradas se reinicia, salvo respaldos restaurados protegidos.
/// Proveedores exige suppliers con CommonFields y variant_suppliers con precio/fecha.
Future<void> _resetDatabaseOnStartup(File file) async {
  if (!await file.exists()) return;
  final connection = sqlite.sqlite3.open(file.path);
  final bool current;
  try {
    current = hasCurrentAppDatabaseSchema(connection);
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
