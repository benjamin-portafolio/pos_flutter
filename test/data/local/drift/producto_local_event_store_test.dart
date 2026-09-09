import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/application/commands/producto_command_service.dart';
import 'package:pos_flutter/application/commands/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';

void main() {
  late AppDatabase db;
  late ProductoDao productoDao;
  late EventDao eventDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    productoDao = ProductoDao(db);
    eventDao = EventDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  for (final mode in [AppMode.standalone, AppMode.serverSync]) {
    for (final dependency in ['none', 'inventory', 'recipe']) {
      test(
        '${mode.name}: elimina variante con $dependency, reutiliza nombre y elimina producto conservando historial',
        () async {
          final projection = DriftProductoProjectionStore(
            productoDao: productoDao,
          );
          final store = _store(mode, db, productoDao, eventDao);
          const refs = [
            LocalEventRef.affects(refType: 'product', refId: 'product_1'),
          ];
          const itemId = '00000000-0000-4000-8000-000000000030';
          if (dependency != 'none') {
            await db
                .into(db.inventoryItems)
                .insert(
                  InventoryItemsCompanion.insert(
                    id: itemId,
                    defaultUnitId: InventoryUnitIds.piece,
                    name: 'Recurso',
                  ),
                );
            await db
                .into(db.inventoryBalances)
                .insert(
                  InventoryBalancesCompanion.insert(
                    inventoryItemId: itemId,
                    quantityOnHandAtomic: 50,
                    quantityAvailableAtomic: 50,
                    lastEventId: 'stock',
                  ),
                );
            await db
                .into(db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion.insert(
                    movementId: 'movement',
                    inventoryItemId: itemId,
                    eventId: 'stock',
                    movementType: 'initial_balance',
                    quantityDeltaAtomic: 50,
                    createdAtLocal: DateTime(2026),
                  ),
                );
          }
          final original = ProductoCreadoPayload.fromJson(
            _advancedEvent().payload,
          );
          final first = original.variantes.first;
          final before = ProductoCreadoPayload.create(
            nombre: original.nombre,
            categoriaId: null,
            saleConfiguration: original.saleConfiguration,
            variantes: [
              ProductoCreadoVariante.create(
                id: first.id,
                nombre: first.nombre,
                precioVentaMenor: first.precioVentaMenor,
                costoEstandarMenor: first.costoEstandarMenor,
                orden: 0,
                inventoryItemId: dependency == 'inventory' ? itemId : null,
                componentesReceta: dependency == 'recipe'
                    ? [
                        ProductoCreadoComponenteReceta.create(
                          inventoryItemId: itemId,
                          quantityAtomic: 1,
                        ),
                      ]
                    : [],
              ),
              original.variantes.last,
            ],
            dependenciasInventario: dependency == 'none'
                ? []
                : [const ProductoCreadoInventarioDependencia(refId: itemId)],
          );
          final creation = _advancedEvent().copyWith(payload: before.toJson());
          await store.appendAndApply(creation, refs: refs);
          final initialRows = await productoDao.obtenerVariantesPorProducto(
            'product_1',
          );
          final after = ProductoCreadoPayload.simple(
            nombre: before.nombre,
            categoriaId: null,
            varianteId: before.variantes.last.id,
            precioVentaMenor: 2000,
          );
          final deletion = creation.copyWith(
            eventId: 'remove_variant',
            eventType: ProductoActualizadoPayload.eventType,
            payload: ProductoActualizadoPayload(
              baseEventId: creation.eventId,
              before: before,
              after: after,
            ).toJson(),
          );
          await store.appendAndApply(deletion, refs: refs);
          final removed = await productoDao.obtenerVariantePorId(first.id);
          expect(removed == null, dependency == 'none');
          if (removed != null) {
            expect(removed.active, isFalse);
            expect(removed.name, first.nombre);
            expect(
              removed.inventoryItemId,
              dependency == 'inventory' ? itemId : null,
            );
            expect(
              await productoDao.obtenerComponentesRecetaPorVariante(first.id),
              dependency == 'recipe' ? hasLength(1) : isEmpty,
            );
          }
          final active = await projection.snapshot('product_1');
          expect(active.variantes.single.id, before.variantes.last.id);
          // Restore pending deletion with exact creation IDs, names and recipes.
          if (mode == AppMode.serverSync) {
            await db.transaction(
              () => projection.applyUpdate(
                deletion,
                before,
                restore: true,
                baseEventId: creation.eventId,
              ),
            );
            expect(
              await productoDao.obtenerVariantesPorProducto('product_1'),
              initialRows,
            );
            expect(
              (await projection.snapshot('product_1')).toJson(),
              before.toJson(),
            );
            await ProductoEventHandler(
              projection,
            ).applyProductoActualizado(deletion);
          }
          final renamed = ProductoCreadoPayload.create(
            nombre: before.nombre,
            categoriaId: null,
            saleConfiguration: before.saleConfiguration,
            variantes: [
              ProductoCreadoVariante.create(
                id: after.variantes.single.id,
                nombre: first.nombre,
                precioVentaMenor: 2000,
                costoEstandarMenor: null,
                orden: 0,
              ),
            ],
          );
          final update = deletion.copyWith(
            eventId: 'reuse_name',
            baseVersion: 2,
            payload: ProductoActualizadoPayload(
              baseEventId: deletion.eventId,
              before: after,
              after: renamed,
            ).toJson(),
          );
          await store.appendAndApply(update, refs: refs);
          final deleteProduct = update.copyWith(
            eventId: 'delete_product',
            baseVersion: 3,
            payload: ProductoActualizadoPayload(
              baseEventId: update.eventId,
              before: renamed,
              after: renamed,
              deleteProduct: true,
            ).toJson(),
          );
          await store.appendAndApply(deleteProduct, refs: refs);
          final product = await productoDao.obtenerProductoPorId('product_1');
          expect(product == null, dependency == 'none');
          if (product != null) expect(product.active, isFalse);
          expect(await productoDao.watchProductosListado().first, isEmpty);
          expect(
            await db.select(db.inventoryItems).get(),
            dependency == 'none' ? isEmpty : hasLength(1),
          );
          if (dependency != 'none') {
            expect(
              (await db.select(db.inventoryBalances).get())
                  .single
                  .quantityOnHandAtomic,
              50,
            );
          }
          if (dependency != 'none') {
            expect(
              (await db.select(db.inventoryMovements).get())
                  .single
                  .quantityDeltaAtomic,
              50,
            );
          }
          expect(
            await db.select(db.eventRefs).get(),
            mode == AppMode.standalone ? isEmpty : isNotEmpty,
          );
          if (mode == AppMode.serverSync) {
            await db.transaction(
              () => projection.applyUpdate(
                deleteProduct,
                renamed,
                restore: true,
                baseEventId: update.eventId,
              ),
            );
            expect(
              (await projection.snapshot('product_1')).toJson(),
              renamed.toJson(),
            );
            expect(
              (await productoDao.obtenerProductoPorId(
                'product_1',
              ))!.createdEventId,
              creation.eventId,
            );
          }
        },
      );
    }
  }

  for (final mode in [AppMode.standalone, AppMode.serverSync]) {
    test(
      '${mode.name} aplica producto y variantes en una transacción',
      () async {
        final store = _store(mode, db, productoDao, eventDao);
        await store.appendAndApply(
          _event(),
          refs: const [
            LocalEventRef.affects(refType: 'product', refId: 'product_1'),
            LocalEventRef.affects(
              refType: 'product_variant',
              refId: '00000000-0000-4000-8000-000000000001',
            ),
          ],
        );

        final product = await productoDao.obtenerProductoPorId('product_1');
        final variants = await productoDao.obtenerVariantesPorProducto(
          'product_1',
        );
        final storedEvent = (await db.select(db.events).get()).single;
        final refs = await db.select(db.eventRefs).get();

        expect(product?.name, 'Café');
        expect(product?.saleMode, 'unit');
        expect(product?.saleUnitId, isNull);
        expect(product?.priceReferenceQuantityAtomic, isNull);
        expect(variants, hasLength(1));
        expect(variants.single.salePriceMinor, 4550);
        expect(
          storedEvent.deliveryStatus,
          mode == AppMode.standalone ? 'not_required' : 'pending',
        );
        expect(refs, mode == AppMode.standalone ? isEmpty : hasLength(2));
      },
    );

    test('${mode.name} aplica varias variantes y refs de nombre', () async {
      final store = _store(mode, db, productoDao, eventDao);
      await store.appendAndApply(
        _advancedEvent(),
        refs: const [
          LocalEventRef.affects(refType: 'product', refId: 'product_1'),
          LocalEventRef.affects(
            refType: 'product_variant',
            refId: '00000000-0000-4000-8000-000000000001',
          ),
          LocalEventRef.requiresUnique(
            refType: 'product_variant_name',
            refId: 'product_1:Z3JhbmRl',
          ),
          LocalEventRef.affects(
            refType: 'product_variant',
            refId: '00000000-0000-4000-8000-000000000002',
          ),
        ],
      );

      final variants = await productoDao.obtenerVariantesPorProducto(
        'product_1',
      );
      expect(variants, hasLength(2));
      expect(variants.map((variant) => variant.name), ['Grande', null]);
      expect(variants.map((variant) => variant.standardCostMinor), [200, 0]);
      expect(variants.map((variant) => variant.sortOrder), [0, 1]);
      expect(
        await db.select(db.eventRefs).get(),
        mode == AppMode.standalone ? isEmpty : hasLength(4),
      );
    });
  }

  for (final mode in [AppMode.standalone, AppMode.serverSync]) {
    test(
      '${mode.name}: actualiza, intercambia variantes, revierte y conserva identidad',
      () async {
        final store = _store(mode, db, productoDao, eventDao);
        final projection = DriftProductoProjectionStore(
          productoDao: productoDao,
        );
        final creation = _advancedEvent();
        const refs = [
          LocalEventRef.affects(refType: 'product', refId: 'product_1'),
        ];
        await store.appendAndApply(creation, refs: refs);
        final before = await projection.snapshot('product_1');
        var after = ProductoCreadoPayload.create(
          nombre: 'Café editado',
          categoriaId: null,
          saleConfiguration: before.saleConfiguration,
          variantes: [
            for (var i = 0; i < 2; i++)
              ProductoCreadoVariante.create(
                id: before.variantes[1 - i].id,
                nombre: i == 0 ? 'Grande' : 'Chico',
                precioVentaMenor: 999,
                costoEstandarMenor: null,
                orden: i,
              ),
          ],
        );
        after = ProductoCreadoPayload.create(
          nombre: after.nombre,
          categoriaId: after.categoriaId,
          saleConfiguration: after.saleConfiguration,
          variantes: [
            ...after.variantes,
            ProductoCreadoVariante.create(
              id: '00000000-0000-4000-8000-000000000099',
              nombre: 'Nueva',
              costoEstandarMenor: null,
              precioVentaMenor: 500,
              orden: 2,
            ),
          ],
        );
        final update = SyncEvent(
          eventId: 'update_1',
          aggregateType: 'product',
          aggregateId: 'product_1',
          eventType: ProductoActualizadoPayload.eventType,
          deviceId: 'device',
          userId: 'user',
          baseVersion: 1,
          createdAtLocal: DateTime(2026),
          payload: ProductoActualizadoPayload(
            baseEventId: creation.eventId,
            before: before,
            after: after,
          ).toJson(),
        );
        await store.appendAndApply(update, refs: refs);
        await ProductoEventHandler(projection).applyProductoActualizado(update);
        final product = (await projection.findProductById('product_1'))!;
        expect(product.nombre, 'Café editado');
        expect(product.version, 2);
        expect(product.createdEventId, creation.eventId);
        expect(
          (await projection.findVariantsByProductId(product.id)).first.id,
          before.variantes.last.id,
        );
        expect(
          (await db.select(db.events).get()).last.deliveryStatus,
          mode == AppMode.standalone ? 'not_required' : 'pending',
        );
        expect(
          await db.select(db.eventRefs).get(),
          mode == AppMode.standalone ? isEmpty : hasLength(2),
        );
        await db.transaction(
          () => projection.applyUpdate(
            update,
            before,
            restore: true,
            baseEventId: creation.eventId,
          ),
        );
        expect(
          (await projection.snapshot(product.id)).toJson(),
          before.toJson(),
        );
        expect((await projection.findProductById(product.id))!.version, 1);
      },
    );
  }

  test(
    'rechaza base obsoleta sin persistir evento ni modificar producto',
    () async {
      final store = _store(AppMode.standalone, db, productoDao, eventDao);
      const refs = [
        LocalEventRef.affects(refType: 'product', refId: 'product_1'),
      ];
      await store.appendAndApply(_event(), refs: refs);
      final projection = DriftProductoProjectionStore(productoDao: productoDao);
      final before = await projection.snapshot('product_1');
      final update = SyncEvent(
        eventId: 'stale',
        aggregateType: 'product',
        aggregateId: 'product_1',
        eventType: ProductoActualizadoPayload.eventType,
        deviceId: 'device',
        userId: 'user',
        baseVersion: 1,
        createdAtLocal: DateTime(2026),
        payload: ProductoActualizadoPayload(
          baseEventId: 'wrong_base',
          before: before,
          after: before,
        ).toJson(),
      );
      await expectLater(
        store.appendAndApply(update, refs: refs),
        throwsStateError,
      );
      expect(await db.select(db.events).get(), hasLength(1));
      expect(
        (await projection.snapshot('product_1')).toJson(),
        before.toJson(),
      );
      final changedSale = ProductoCreadoPayload.create(
        nombre: before.nombre,
        categoriaId: null,
        saleConfiguration: MeasuredSaleConfiguration(
          saleUnitId: InventoryUnitIds.kilogram,
          priceReferenceQuantityAtomic: 1000,
        ),
        variantes: before.variantes,
      );
      expect(
        () => ProductoActualizadoPayload(
          baseEventId: 'event_1',
          before: before,
          after: changedSale,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'el command service normaliza edición, preserva IDs y rechaza formulario obsoleto',
    () async {
      final store = _store(AppMode.standalone, db, productoDao, eventDao);
      final projection = DriftProductoProjectionStore(productoDao: productoDao);
      final service = ProductoCommandService(
        eventStore: store,
        commandContext: const LocalCommandContext(
          deviceId: 'device',
          userId: 'user',
        ),
        categoriaProjectionStore: DriftCategoriaProjectionStore(
          categoriaDao: CategoriaDao(db),
        ),
        productoProjectionStore: projection,
        syncedEventHistory: DriftSyncPersistence(
          db: db,
          eventDao: eventDao,
          eventRefDao: EventRefDao(db),
          syncCheckpointDao: SyncCheckpointDao(db),
        ),
        unidadInventarioRepository: UnidadInventarioRepositoryImpl(
          unitDao: UnitDao(db),
        ),
      );
      await service.crearArticulo(
        const CrearArticuloCommand(nombre: 'Café', precioVenta: '10'),
      );
      final product = (await db.select(db.products).get()).single;
      final variant = (await db.select(db.productVariants).get()).single;
      const command = CrearArticuloCommand.conVariantes(
        nombre: '  Nuevo  ',
        variantes: [
          CrearArticuloVarianteCommand(
            nombre: '  Grande ',
            precioVenta: '20.50',
            costoEstandar: '0',
          ),
          CrearArticuloVarianteCommand(
            nombre: 'Nueva',
            precioVenta: '5',
            costoEstandar: null,
          ),
        ],
      );
      await service.actualizarArticulo(
        productId: product.id,
        baseEventId: product.lastEventId!,
        command: command,
        variantIds: [variant.id, null],
      );
      final state = await projection.snapshot(product.id);
      expect(state.nombre, 'Nuevo');
      expect(state.variantes, hasLength(2));
      expect(state.variantes.last.id, isNot(variant.id));
      expect(state.variantes.first.id, variant.id);
      expect(state.variantes.first.nombre, 'Grande');
      expect(state.variantes.first.precioVentaMenor, 2050);
      expect(state.variantes.first.costoEstandarMenor, 0);
      await expectLater(
        service.actualizarArticulo(
          productId: product.id,
          baseEventId: product.lastEventId!,
          command: command,
          variantIds: [variant.id, null],
        ),
        throwsStateError,
      );
      expect(await db.select(db.events).get(), hasLength(2));
      expect(await db.select(db.eventRefs).get(), isEmpty);
      var current = (await projection.findProductById(product.id))!;
      await service.actualizarArticulo(
        productId: product.id,
        baseEventId: current.lastEventId!,
        variantIds: [state.variantes.last.id],
        command: const CrearArticuloCommand.conVariantes(
          nombre: 'Nuevo',
          variantes: [
            CrearArticuloVarianteCommand(
              nombre: 'Nueva',
              precioVenta: '5',
              costoEstandar: null,
            ),
          ],
        ),
      );
      expect(
        (await projection.snapshot(product.id)).variantes.single.id,
        state.variantes.last.id,
      );
      current = (await projection.findProductById(product.id))!;
      await service.eliminarArticulo(
        productId: product.id,
        baseEventId: current.lastEventId!,
      );
      expect(await projection.findProductById(product.id), isNull);
      expect(await db.select(db.eventRefs).get(), isEmpty);
      expect(
        (await db.select(db.events).get()).every(
          (e) => e.deliveryStatus == 'not_required',
        ),
        isTrue,
      );
    },
  );

  test('el handler es idempotente para el mismo evento', () async {
    final projectionStore = DriftProductoProjectionStore(
      productoDao: productoDao,
    );
    final handler = ProductoEventHandler(projectionStore);

    await handler.applyProductoCreado(_event());
    await handler.applyProductoCreado(_event());

    expect(await db.select(db.products).get(), hasLength(1));
    expect(await db.select(db.productVariants).get(), hasLength(1));
  });

  test('server_sync proyecta measured y persiste la ref unit', () async {
    final store = _store(AppMode.serverSync, db, productoDao, eventDao);
    await store.appendAndApply(
      _event(
        saleConfiguration: MeasuredSaleConfiguration(
          saleUnitId: InventoryUnitIds.kilogram,
          priceReferenceQuantityAtomic: 1000,
        ),
      ),
      refs: const [
        LocalEventRef.affects(refType: 'product', refId: 'product_1'),
        LocalEventRef.affects(
          refType: 'product_variant',
          refId: '00000000-0000-4000-8000-000000000001',
        ),
        LocalEventRef.uses(refType: 'unit', refId: InventoryUnitIds.kilogram),
      ],
    );

    final product = await productoDao.obtenerProductoPorId('product_1');
    final refs = await db.select(db.eventRefs).get();
    expect(product?.saleMode, 'measured');
    expect(product?.saleUnitId, InventoryUnitIds.kilogram);
    expect(product?.priceReferenceQuantityAtomic, 1000);
    expect(refs.map((ref) => ref.refType), [
      'product',
      'product_variant',
      'unit',
    ]);
  });

  test(
    'un evento remoto reemplaza una colisión de variante local pendiente',
    () async {
      final projectionStore = DriftProductoProjectionStore(
        productoDao: productoDao,
      );
      final handler = ProductoEventHandler(projectionStore);
      await handler.applyProductoCreado(_event());

      await handler.applyProductoCreado(
        _event(
          eventId: 'remote_event',
          productId: 'official_product',
          serverSequence: 10,
        ),
      );

      expect(await productoDao.obtenerProductoPorId('product_1'), isNull);
      expect(
        await productoDao.obtenerProductoPorId('official_product'),
        isNotNull,
      );
      final variants = await db.select(db.productVariants).get();
      expect(variants, hasLength(1));
      expect(variants.single.productId, 'official_product');
      expect(variants.single.lastServerSequence, 10);
    },
  );
}

DriftLocalEventStore _store(
  AppMode mode,
  AppDatabase db,
  ProductoDao productoDao,
  EventDao eventDao,
) {
  return DriftLocalEventStore(
    db: db,
    eventDao: eventDao,
    eventRefDao: EventRefDao(db),
    eventProcessor: EventProcessor(
      handlers: productoEventHandlers(
        ProductoEventHandler(
          DriftProductoProjectionStore(productoDao: productoDao),
          inventoryProjectionStore: DriftInventoryProjectionStore(
            inventoryDao: InventoryDao(db),
            unitDao: UnitDao(db),
          ),
        ),
      ),
    ),
    appConfigController: AppConfigController(
      AppConfig.initial.copyWith(mode: mode, setupCompleted: true),
    ),
  );
}

SyncEvent _event({
  String eventId = 'event_1',
  String productId = 'product_1',
  int? serverSequence,
  SaleConfiguration saleConfiguration = const UnitSaleConfiguration(),
}) {
  return SyncEvent(
    eventId: eventId,
    aggregateType: ProductoCreadoPayload.aggregateType,
    aggregateId: productId,
    eventType: ProductoCreadoPayload.eventType,
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    serverSequence: serverSequence,
    createdAtLocal: DateTime(2026),
    payload: ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: null,
      varianteId: '00000000-0000-4000-8000-000000000001',
      precioVentaMenor: 4550,
      saleConfiguration: saleConfiguration,
    ).toJson(),
  );
}

SyncEvent _advancedEvent() {
  return SyncEvent(
    eventId: 'event_advanced',
    aggregateType: ProductoCreadoPayload.aggregateType,
    aggregateId: 'product_1',
    eventType: ProductoCreadoPayload.eventType,
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026),
    payload: ProductoCreadoPayload.create(
      nombre: 'Café',
      categoriaId: null,
      saleConfiguration: const UnitSaleConfiguration(),
      variantes: [
        ProductoCreadoVariante.create(
          id: '00000000-0000-4000-8000-000000000001',
          nombre: 'Grande',
          precioVentaMenor: 1000,
          costoEstandarMenor: 200,
          orden: 0,
        ),
        ProductoCreadoVariante.create(
          id: '00000000-0000-4000-8000-000000000002',
          nombre: null,
          precioVentaMenor: 1200,
          costoEstandarMenor: 0,
          orden: 1,
        ),
      ],
    ).toJson(),
  );
}
