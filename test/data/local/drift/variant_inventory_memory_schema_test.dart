import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

/// Fase 1 · seguimiento de existencias.
///
/// Comprueba el mapeo físico de los dos elementos nuevos del contrato rev. 1 §5:
/// la procedencia nullable en `inventory_items` y la memoria de variante. No
/// hay `onUpgrade`: la política vigente es detección de esquema y borrado en
/// desarrollo, así que una base anterior se reconstruye, no se migra.
void main() {
  test(
    'el esquema actual declara origin_variant_id y variant_inventory_memory',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pos-variant-memory-schema-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/schema.sqlite')),
      );
      addTearDown(database.close);

      expect(database.schemaVersion, 8);

      final itemColumns = await database
          .customSelect('PRAGMA table_info(inventory_items)')
          .get();
      final originColumn = itemColumns.firstWhere(
        (row) => row.read<String>('name') == 'origin_variant_id',
      );
      // Nullable e indexado, sin unicidad: dos recursos pueden compartir
      // procedencia y ninguno la necesita.
      expect(originColumn.read<int>('notnull'), 0);
      final itemIndexes = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'inventory_items'",
          )
          .get();
      expect(
        itemIndexes.map((row) => row.read<String>('name')),
        contains('ix_inventory_items_origin_variant'),
      );

      final memoryColumns = await database
          .customSelect('PRAGMA table_info(variant_inventory_memory)')
          .get();
      expect(memoryColumns.map((row) => row.read<String>('name')).toSet(), {
        'variant_id',
        'inventory_item_id',
        'source_event_id',
        'source_server_sequence',
      });
      // La procedencia de la memoria es opcional: mientras el estado es solo
      // local no hay secuencia oficial que la acredite.
      final sequenceColumn = memoryColumns.firstWhere(
        (row) => row.read<String>('name') == 'source_server_sequence',
      );
      expect(sequenceColumn.read<int>('notnull'), 0);

      final memoryIndexes = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'variant_inventory_memory'",
          )
          .get();
      expect(
        memoryIndexes.map((row) => row.read<String>('name')),
        contains('ix_variant_inventory_memory_item'),
      );

      // Cascadas en ambos sentidos: borrar cualquiera retira la memoria y no
      // toca el otro lado del vínculo.
      final memoryForeignKeys = await database
          .customSelect('PRAGMA foreign_key_list(variant_inventory_memory)')
          .get();
      final cascades = {
        for (final row in memoryForeignKeys)
          '${row.read<String>('table')}:${row.read<String>('on_delete')}',
      };
      expect(cascades, {'product_variants:CASCADE', 'inventory_items:CASCADE'});
    },
  );

  test(
    'borrar el recurso retira solo su memoria y conserva la variante',
    () async {
      final database = await _seededDatabase();
      addTearDown(database.close);

      // El vínculo directo protege el recurso (RESTRICT): la memoria no lo
      // exime. Se replica el orden real del descarte: primero se suelta el
      // vínculo, después se borra el recurso.
      expect(
        () => (database.delete(
          database.inventoryItems,
        )..where((row) => row.id.equals(_recursoAutogenerado))).go(),
        throwsA(isA<SqliteException>()),
      );
      await (database.update(database.productVariants)
            ..where((row) => row.id.equals(_variante250G)))
          .write(const ProductVariantsCompanion(inventoryItemId: Value(null)));
      await (database.delete(
        database.inventoryItems,
      )..where((row) => row.id.equals(_recursoAutogenerado))).go();

      // Solo se retira su memoria; la variante y su recurso compartido siguen.
      expect(
        await (database.select(
          database.variantInventoryMemory,
        )..where((row) => row.variantId.equals(_variante250G))).get(),
        isEmpty,
      );
      expect(
        await (database.select(
          database.productVariants,
        )..where((row) => row.id.equals(_variante250G))).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.productVariants).get(),
        hasLength(3),
      );
    },
  );

  test(
    'borrar la variante retira solo su memoria y conserva el recurso',
    () async {
      final database = await _seededDatabase();
      addTearDown(database.close);

      await (database.delete(
        database.productVariants,
      )..where((row) => row.id.equals(_variante250G))).go();

      // La variante eliminada no arrastra a las otras memorias.
      final memories = await database
          .select(database.variantInventoryMemory)
          .get();
      expect(
        memories.map((row) => row.variantId),
        isNot(contains(_variante250G)),
      );
      expect(memories, hasLength(1));
      // El recurso de la variante eliminada sobrevive: la cascada es de una
      // sola dirección y no hay `ON DELETE CASCADE` desde variants a items.
      expect(
        await (database.select(
          database.inventoryItems,
        )..where((row) => row.id.equals(_recursoReceta))).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.inventoryItems).get(),
        hasLength(3),
      );
    },
  );

  test(
    'la memoria admite recursos compartidos y conserva su evidencia',
    () async {
      final database = await _seededDatabase();
      addTearDown(database.close);

      // El índice sobre inventory_item_id no es único: dos variantes pueden
      // recordar el mismo recurso.
      await database
          .into(database.variantInventoryMemory)
          .insert(
            VariantInventoryMemoryCompanion.insert(
              variantId: _variante1kg,
              inventoryItemId: _recursoAutogenerado,
              sourceEventId: 'event-memoria-compartida',
            ),
          );
      expect(
        await (database.select(
              database.variantInventoryMemory,
            )..where((row) => row.inventoryItemId.equals(_recursoAutogenerado)))
            .get(),
        hasLength(2),
      );
      // Una misma variante no admite dos memorias: la PK lo impide.
      expect(
        () => database
            .into(database.variantInventoryMemory)
            .insert(
              VariantInventoryMemoryCompanion.insert(
                variantId: _variante1kg,
                inventoryItemId: _recursoReceta,
                sourceEventId: 'event-memoria-duplicada',
              ),
            ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('la procedencia se lee y se escribe sin inventarla', () async {
    final database = await _seededDatabase();
    addTearDown(database.close);

    final conOrigen = await (database.select(
      database.inventoryItems,
    )..where((row) => row.id.equals(_recursoAutogenerado))).getSingle();
    expect(conOrigen.originVariantId, _variante250G);

    // Los recursos legados quedan en null = desconocido, no en un UUID
    // inventado a partir del nombre o de la variante más cercana.
    final legado = await (database.select(
      database.inventoryItems,
    )..where((row) => row.id.equals(_recursoLegado))).getSingle();
    expect(legado.originVariantId, isA<Null>());

    await (database.update(
      database.inventoryItems,
    )..where((row) => row.id.equals(_recursoLegado))).write(
      const InventoryItemsCompanion(originVariantId: Value(_variante1kg)),
    );
    expect(
      (await (database.select(
            database.inventoryItems,
          )..where((row) => row.id.equals(_recursoLegado))).getSingle())
          .originVariantId,
      _variante1kg,
    );
  });
}

const _productoMolido = 'a1000000-0000-4000-8000-000000000001';
const _variante250G = 'a2000000-0000-4000-8000-000000000001';
const _variante1kg = 'a2000000-0000-4000-8000-000000000002';
const _recursoAutogenerado = 'a3000000-0000-4000-8000-000000000001';
const _recursoLegado = 'a3000000-0000-4000-8000-000000000002';
const _recursoReceta = 'a4000000-0000-4000-8000-000000000001';
// Las unidades son datos de catálogo sembrados por la base, no por el contrato
// de procedencia: se usa la identidad real del gramo para no pelear con la FK.
const _unidadGramo = InventoryUnitIds.gram;

/// Base temporal con el estado previo a la fase 1: un recurso con procedencia,
/// un recurso legado sin ella y dos variantes que comparten el recurso.
Future<AppDatabase> _seededDatabase() async {
  final directory = await Directory.systemTemp.createTemp(
    'pos-variant-memory-cascade-',
  );
  addTearDown(() => directory.delete(recursive: true));
  final database = AppDatabase.forTesting(
    NativeDatabase(File('${directory.path}/cascade.sqlite')),
  );

  await database
      .into(database.products)
      .insert(
        ProductsCompanion.insert(
          id: _productoMolido,
          name: 'Café molido',
          createdEventId: const Value('event-producto'),
          lastEventId: const Value('event-producto'),
        ),
      );
  await database
      .into(database.inventoryItems)
      .insert(
        InventoryItemsCompanion.insert(
          id: _recursoAutogenerado,
          name: 'Café molido 250 g',
          defaultUnitId: _unidadGramo,
          createdEventId: const Value('event-alta'),
          lastEventId: const Value('event-alta'),
          originVariantId: const Value(_variante250G),
        ),
      );
  await database
      .into(database.inventoryItems)
      .insert(
        InventoryItemsCompanion.insert(
          id: _recursoLegado,
          name: 'Café molido (2019)',
          defaultUnitId: _unidadGramo,
          createdEventId: const Value('event-alta-legado'),
          lastEventId: const Value('event-alta-legado'),
        ),
      );
  await database
      .into(database.inventoryItems)
      .insert(
        InventoryItemsCompanion.insert(
          id: _recursoReceta,
          name: 'Café en grano 1 kg',
          defaultUnitId: _unidadGramo,
          createdEventId: const Value('event-alta-receta'),
          lastEventId: const Value('event-alta-receta'),
        ),
      );
  for (final variant in [
    (_variante250G, 0, _recursoAutogenerado),
    (_variante1kg, 1, null as String?),
    ('a2000000-0000-4000-8000-000000000004', 2, _recursoReceta),
  ]) {
    await database
        .into(database.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: variant.$1,
            productId: _productoMolido,
            salePriceMinor: 4500,
            sortOrder: variant.$2,
            inventoryItemId: Value(variant.$3),
            createdEventId: const Value('event-producto'),
            lastEventId: const Value('event-producto'),
          ),
        );
  }
  await database
      .into(database.variantInventoryMemory)
      .insert(
        VariantInventoryMemoryCompanion.insert(
          variantId: _variante250G,
          inventoryItemId: _recursoAutogenerado,
          sourceEventId: 'event-producto',
          sourceServerSequence: const Value(41),
        ),
      );
  await database
      .into(database.variantInventoryMemory)
      .insert(
        VariantInventoryMemoryCompanion.insert(
          variantId: 'a2000000-0000-4000-8000-000000000004',
          inventoryItemId: _recursoReceta,
          sourceEventId: 'event-producto',
        ),
      );

  return database;
}
