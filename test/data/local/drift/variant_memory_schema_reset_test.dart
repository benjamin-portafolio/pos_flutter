import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// SEG-28 (fase 1) y punto 8 de la fase: la política vigente no es `onUpgrade`
/// sino detección de esquema en el arranque. Una base anterior a la fase 1 se
/// reconstruye; una base del esquema actual se conserva entre arranques, con su
/// procedencia y su memoria intactas.
///
/// Todo corre sobre archivos temporales: nunca se abre la base real del usuario.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'pos_variant_memory_reset_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test('recrea una base sin memoria de variante y conserva datos después', () async {
    // Base del esquema anterior a la fase 1: todo lo demás está al día pero
    // faltan la tabla `variant_inventory_memory` y `origin_variant_id`.
    final initial = AppDatabase();
    // El índice depende de la columna: se retira primero para simular una base
    // creada antes de la fase 1.
    await initial.customStatement(
      'DROP INDEX ix_inventory_items_origin_variant',
    );
    await initial.customStatement(
      'ALTER TABLE inventory_items DROP COLUMN origin_variant_id',
    );
    await initial.customStatement('DROP TABLE variant_inventory_memory');
    await initial.customStatement('CREATE TABLE obsolete_marker (id TEXT)');
    await initial.customStatement(
      "INSERT INTO inventory_items (id, name, default_unit_id, created_event_id, last_event_id) "
      "VALUES ('legacy-item', 'Café molido (2019)', '${InventoryUnitIds.gram}', "
      "'event-legado', 'event-legado')",
    );
    await initial.close();

    // Primer arranque: se detecta el esquema anterior y se reconstruye.
    var database = AppDatabase();
    final variantColumns = await database
        .customSelect('PRAGMA table_info(inventory_items)')
        .get();
    expect(
      variantColumns.map((row) => row.read<String>('name')),
      contains('origin_variant_id'),
    );
    expect(
      await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'obsolete_marker'",
          )
          .get(),
      isEmpty,
    );
    // El recurso legado se perdió con la reconstrucción, y su procedencia no
    // se inventa: la base nueva empieza sin procedencia.
    expect(await database.select(database.inventoryItems).get(), isEmpty);

    // Datos propios del esquema actual, incluida la memoria.
    await database
        .into(database.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            id: 'recurso-actual',
            name: 'Café molido 250 g',
            defaultUnitId: InventoryUnitIds.gram,
            createdEventId: const Value('event-alta'),
            lastEventId: const Value('event-alta'),
            originVariantId: const Value(
              'a2000000-0000-4000-8000-000000000001',
            ),
          ),
        );
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: 'producto-actual',
            name: 'Café molido',
            createdEventId: const Value('event-producto'),
            lastEventId: const Value('event-producto'),
          ),
        );
    await database
        .into(database.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: 'a2000000-0000-4000-8000-000000000001',
            productId: 'producto-actual',
            salePriceMinor: 4500,
            sortOrder: 0,
            createdEventId: const Value('event-producto'),
            lastEventId: const Value('event-producto'),
          ),
        );
    await database
        .into(database.variantInventoryMemory)
        .insert(
          VariantInventoryMemoryCompanion.insert(
            variantId: 'a2000000-0000-4000-8000-000000000001',
            inventoryItemId: 'recurso-actual',
            sourceEventId: 'event-producto',
            sourceServerSequence: const Value(41),
          ),
        );
    await database.close();

    // Segundo arranque: la base ya es del esquema actual y se conserva entera.
    database = AppDatabase();
    final memory = await database.select(database.variantInventoryMemory).get();
    expect(memory, hasLength(1));
    expect(memory.single.inventoryItemId, 'recurso-actual');
    expect(memory.single.sourceServerSequence, 41);
    final item = await database.select(database.inventoryItems).get();
    expect(item.single.originVariantId, 'a2000000-0000-4000-8000-000000000001');
    await database.close();
  });

  for (final restored in [false, true]) {
    test('base sin origin_variant_id: respaldo restaurado=$restored', () async {
      final initial = AppDatabase();
      await initial.customStatement(
        'DROP INDEX ix_inventory_items_origin_variant',
      );
      await initial.customStatement(
        'ALTER TABLE inventory_items DROP COLUMN origin_variant_id',
      );
      await initial.close();
      if (restored) await markAppDatabaseAsRestored();

      final database = AppDatabase();
      if (restored) {
        // Un respaldo de un esquema anterior se rechaza, no se destruye.
        await expectLater(
          database.select(database.products).get(),
          throwsStateError,
        );
        await expectLater(database.close(), throwsStateError);
        final preserved = sqlite.sqlite3.open((await appDatabaseFile()).path);
        try {
          expect(
            preserved
                .select('PRAGMA table_info(inventory_items)')
                .map((column) => column['name']),
            isNot(contains('origin_variant_id')),
          );
        } finally {
          preserved.close();
        }
      } else {
        expect(
          (await database
                  .customSelect('PRAGMA table_info(inventory_items)')
                  .get())
              .map((row) => row.read<String>('name')),
          contains('origin_variant_id'),
        );
        expect(database.schemaVersion, 8);
        await database.close();
      }
    });
  }
}
