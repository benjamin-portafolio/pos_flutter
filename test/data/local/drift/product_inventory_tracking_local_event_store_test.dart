import 'package:pos_flutter/application/commands/producto_command_service.dart';
import 'package:pos_flutter/application/commands/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';

void main() {
  late AppDatabase db;
  late DriftLocalEventStore eventStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final inventoryStore = DriftInventoryProjectionStore(
      inventoryDao: InventoryDao(db),
      unitDao: UnitDao(db),
    );
    final productStore = DriftProductoProjectionStore(
      productoDao: ProductoDao(db),
    );
    eventStore = DriftLocalEventStore(
      db: db,
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      eventProcessor: EventProcessor(
        handlers: {
          ...inventoryEventHandlers(InventoryEventHandler(inventoryStore)),
          ...productoEventHandlers(
            ProductoEventHandler(
              productStore,
              inventoryProjectionStore: inventoryStore,
            ),
          ),
        },
      ),
      appConfigController: AppConfigController(
        AppConfig.initial.copyWith(
          mode: AppMode.standalone,
          setupCompleted: true,
        ),
      ),
    );
  });

  tearDown(() => db.close());

  test('edita seguimiento y receta sin reescribir existencias', () async {
    await eventStore.appendAndApplyBatchAtomically(
      _entries(productInventoryItemId: _inventoryItemId),
    );
    final projection = DriftProductoProjectionStore(
      productoDao: ProductoDao(db),
    );
    final service = ProductoCommandService(
      eventStore: eventStore,
      commandContext: const LocalCommandContext(
        deviceId: 'device',
        userId: 'user',
      ),
      categoriaProjectionStore: DriftCategoriaProjectionStore(
        categoriaDao: CategoriaDao(db),
      ),
      productoProjectionStore: projection,
      inventoryProjectionStore: DriftInventoryProjectionStore(
        inventoryDao: InventoryDao(db),
        unitDao: UnitDao(db),
      ),
      syncedEventHistory: DriftSyncPersistence(
        db: db,
        eventDao: EventDao(db),
        eventRefDao: EventRefDao(db),
        syncCheckpointDao: SyncCheckpointDao(db),
      ),
      unidadInventarioRepository: UnidadInventarioRepositoryImpl(
        unitDao: UnitDao(db),
      ),
    );
    final id = (await db.select(db.products).get()).single.id;
    final variantId = (await db.select(db.productVariants).get()).single.id;
    Future<void> save({
      String? unit,
      List<CrearArticuloRecipeComponentCommand> recipe = const [],
    }) async {
      final product = (await projection.findProductById(id))!;
      await service.actualizarArticulo(
        productId: id,
        baseEventId: product.lastEventId!,
        variantIds: [variantId],
        command: CrearArticuloCommand.conVariantes(
          nombre: 'Agua editada',
          variantes: [
            CrearArticuloVarianteCommand(
              nombre: 'Grande',
              precioVenta: '30',
              costoEstandar: null,
              inventoryUnitId: unit,
              recipeComponents: recipe,
            ),
          ],
        ),
      );
    }

    await save(unit: InventoryUnitIds.piece);
    expect(
      (await projection.snapshot(id)).variantes.single.inventoryItemId,
      _inventoryItemId,
    );
    expect(await db.select(db.inventoryItems).get(), hasLength(1));
    await save(
      recipe: const [
        CrearArticuloRecipeComponentCommand(
          inventoryItemId: _inventoryItemId,
          quantity: '3',
        ),
      ],
    );
    expect(
      (await projection.snapshot(id)).variantes.single.inventoryItemId,
      isNull,
    );
    expect(
      (await db.select(db.recipeComponents).get()).single.quantityAtomic,
      3,
    );
    expect(
      (await db.select(db.inventoryBalances).get()).single.quantityOnHandAtomic,
      15,
    );
    await save();
    expect(await db.select(db.recipeComponents).get(), isEmpty);
    expect(await db.select(db.inventoryMovements).get(), hasLength(1));
    await save(unit: InventoryUnitIds.piece);
    expect(
      (await projection.snapshot(id)).variantes.single.inventoryItemId,
      isNotNull,
    );
    expect(await db.select(db.inventoryItems).get(), hasLength(2));
    expect(await db.select(db.inventoryMovements).get(), hasLength(1));
    expect(await db.select(db.eventRefs).get(), isEmpty);
  });

  test('crea recurso, saldo, movimiento y vínculo en un solo lote', () async {
    await eventStore.appendAndApplyBatchAtomically(
      _entries(productInventoryItemId: _inventoryItemId),
    );

    expect(await db.select(db.events).get(), hasLength(2));
    expect(await db.select(db.inventoryItems).get(), hasLength(1));
    expect(
      (await db.select(db.inventoryBalances).get()).single.quantityOnHandAtomic,
      15,
    );
    expect(await db.select(db.inventoryMovements).get(), hasLength(1));
    expect(
      (await db.select(db.productVariants).get()).single.inventoryItemId,
      _inventoryItemId,
    );
    expect(await db.select(db.eventRefs).get(), isEmpty);
  });

  test('revierte el recurso si falla el vínculo del artículo', () async {
    await expectLater(
      eventStore.appendAndApplyBatchAtomically(
        _entries(productInventoryItemId: _missingInventoryItemId),
      ),
      throwsA(isA<StateError>()),
    );

    expect(await db.select(db.events).get(), isEmpty);
    expect(await db.select(db.inventoryItems).get(), isEmpty);
    expect(await db.select(db.inventoryBalances).get(), isEmpty);
    expect(await db.select(db.inventoryMovements).get(), isEmpty);
    expect(await db.select(db.products).get(), isEmpty);
    expect(await db.select(db.productVariants).get(), isEmpty);
  });

  test('persiste los componentes de receta junto con el artículo', () async {
    await eventStore.appendAndApplyBatchAtomically(_recipeEntries());

    final variants = await db.select(db.productVariants).get();
    final components = await db.select(db.recipeComponents).get();
    expect(variants.single.inventoryItemId, isNull);
    expect(components, hasLength(1));
    expect(components.single.variantId, variants.single.id);
    expect(components.single.inventoryItemId, _inventoryItemId);
    expect(components.single.quantityAtomic, 2);
    final ingredients = await InventoryDao(
      db,
    ).watchRecursos(filtro: 'ingredients').first;
    expect(ingredients.map((resource) => resource.id), [_inventoryItemId]);
    expect(await db.select(db.eventRefs).get(), isEmpty);
  });
}

const _inventoryItemId = '20000000-0000-4000-8000-000000000001';
const _missingInventoryItemId = '20000000-0000-4000-8000-000000000099';

List<LocalEventAppend> _entries({required String productInventoryItemId}) {
  final createdAt = DateTime.utc(2026, 8, 26);
  final resourceEvent = SyncEvent(
    eventId: '40000000-0000-4000-8000-000000000001',
    aggregateType: RecursoInventarioCreadoPayload.aggregateType,
    aggregateId: _inventoryItemId,
    eventType: RecursoInventarioCreadoPayload.eventType,
    deviceId: 'device-test',
    userId: 'user-test',
    baseVersion: 1,
    createdAtLocal: createdAt,
    payload: RecursoInventarioCreadoPayload.create(
      inventoryItemId: _inventoryItemId,
      name: 'Agua mineral',
      defaultUnitId: InventoryUnitIds.piece,
      initialMovement: InitialInventoryMovementPayload.create(
        movementId: '30000000-0000-4000-8000-000000000001',
        movementType: TipoMovimientoInventario.initialBalance,
        quantityDeltaAtomic: 15,
      ),
    ).toJson(),
  );
  final productEvent = SyncEvent(
    eventId: '40000000-0000-4000-8000-000000000002',
    aggregateType: ProductoCreadoPayload.aggregateType,
    aggregateId: '10000000-0000-4000-8000-000000000001',
    eventType: ProductoCreadoPayload.eventType,
    deviceId: 'device-test',
    userId: 'user-test',
    baseVersion: 1,
    createdAtLocal: createdAt,
    payload: ProductoCreadoPayload.create(
      nombre: 'Agua mineral',
      categoriaId: null,
      saleConfiguration: const UnitSaleConfiguration(),
      variantes: [
        ProductoCreadoVariante.create(
          id: '10000000-0000-4000-8000-000000000002',
          nombre: null,
          precioVentaMenor: 2500,
          costoEstandarMenor: null,
          inventoryItemId: productInventoryItemId,
          esPredeterminada: true,
          orden: 0,
        ),
      ],
      dependenciasInventario: [
        ProductoCreadoInventarioDependencia(
          refId: productInventoryItemId,
          dependsOnEventId: resourceEvent.eventId,
        ),
      ],
    ).toJson(),
  );
  return [
    LocalEventAppend(
      event: resourceEvent,
      refs: const [
        LocalEventRef.affects(
          refType: 'inventory_item',
          refId: _inventoryItemId,
        ),
      ],
    ),
    LocalEventAppend(
      event: productEvent,
      refs: [
        const LocalEventRef.affects(
          refType: 'product',
          refId: '10000000-0000-4000-8000-000000000001',
        ),
        LocalEventRef.uses(
          refType: 'inventory_item',
          refId: productInventoryItemId,
        ),
      ],
    ),
  ];
}

List<LocalEventAppend> _recipeEntries() {
  final entries = _entries(productInventoryItemId: _inventoryItemId);
  final resourceEvent = entries.first.event;
  final directProductEvent = entries.last.event;
  final recipeProductEvent = SyncEvent(
    eventId: directProductEvent.eventId,
    aggregateType: directProductEvent.aggregateType,
    aggregateId: directProductEvent.aggregateId,
    eventType: directProductEvent.eventType,
    deviceId: directProductEvent.deviceId,
    userId: directProductEvent.userId,
    baseVersion: directProductEvent.baseVersion,
    createdAtLocal: directProductEvent.createdAtLocal,
    payload: ProductoCreadoPayload.create(
      nombre: 'Agua preparada',
      categoriaId: null,
      saleConfiguration: const UnitSaleConfiguration(),
      variantes: [
        ProductoCreadoVariante.create(
          id: '10000000-0000-4000-8000-000000000002',
          nombre: null,
          precioVentaMenor: 2500,
          costoEstandarMenor: null,
          componentesReceta: [
            ProductoCreadoComponenteReceta.create(
              inventoryItemId: _inventoryItemId,
              quantityAtomic: 2,
            ),
          ],
          esPredeterminada: true,
          orden: 0,
        ),
      ],
      dependenciasInventario: [
        ProductoCreadoInventarioDependencia(
          refId: _inventoryItemId,
          dependsOnEventId: resourceEvent.eventId,
        ),
      ],
    ).toJson(),
  );
  return [
    entries.first,
    LocalEventAppend(
      event: recipeProductEvent,
      refs: const [
        LocalEventRef.affects(
          refType: 'product',
          refId: '10000000-0000-4000-8000-000000000001',
        ),
        LocalEventRef.uses(refType: 'inventory_item', refId: _inventoryItemId),
      ],
    ),
  ];
}
