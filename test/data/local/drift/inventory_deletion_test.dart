import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_variant_inventory_memory_store.dart';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/inventario/editar_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/inventario/eliminar_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/inventario/inventory_command_service.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_eliminada_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_registry.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_eliminado_payload.dart';
import 'package:pos_flutter/application/sync/projections/inventory_projection_store.dart';
import 'package:pos_flutter/application/sync/revalidation/inventory_pending_event_validator.dart';
import 'package:pos_flutter/application/sync/revalidation/pending_event_dependency_resolver.dart';
import 'package:pos_flutter/application/sync/revalidation/pending_conflict.dart';
import 'package:pos_flutter/application/sync/remote_event_preparer.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_variant_inventory_tracking_store.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';

void main() {
  for (final mode in [AppMode.standalone, AppMode.serverSync]) {
    group(mode.name, () {
      late _Fixture f;
      setUp(() => f = _Fixture(mode));
      tearDown(() => f.db.close());

      test(
        'baja conserva historial, saldo y referencias según modo; replay no resucita',
        () async {
          final id = await f.create();
          await f.service.registrarMovimiento(
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: id,
              movementType: TipoMovimientoInventario.manualAdjustment,
              movementReason: 'Conteo físico',
              quantityDeltaAtomic: 3,
            ),
          );
          await f.service.registrarMovimiento(
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: id,
              movementType: TipoMovimientoInventario.manualAdjustment,
              movementReason: 'Conteo físico',
              quantityDeltaAtomic: -3,
            ),
          );
          final creation = await f.persistence.eventById(
            (await f.db.select(f.db.events).get()).first.eventId,
          );
          await f.remove(id);
          final item = await f.projection.findItemById(id);
          final deletion = await f.deletion();
          expect(item!.active, false);
          expect(item.version, 4);
          expect(await f.db.inventoryDao.watchRecursos().first, isEmpty);
          expect(
            await f.db.select(f.db.inventoryMovements).get(),
            hasLength(2),
          );
          expect(
            (await f.projection.findBalanceByItemId(id))!.quantityOnHandAtomic,
            0,
          );
          expect(
            deletion.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          final refs = await f.db.select(f.db.eventRefs).get();
          expect(refs, mode == AppMode.standalone ? isEmpty : hasLength(7));
          await f.handler.applyRecursoInventarioEliminado(deletion);
          if (creation != null) {
            await f.handler.applyRecursoInventarioCreado(creation);
          }
          expect((await f.projection.findItemById(id))!.active, false);
        },
      );

      for (final quantity in [-1, 1]) {
        test('saldo $quantity bloquea sin persistir evento de baja', () async {
          final id = await f.create();
          await f.service.registrarMovimiento(
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: id,
              movementType: TipoMovimientoInventario.manualAdjustment,
              movementReason: 'Conteo físico',
              quantityDeltaAtomic: quantity,
            ),
          );
          await expectLater(
            f.remove(id),
            throwsA(isA<InventoryProjectionConflict>()),
          );
          expect((await f.projection.findItemById(id))!.active, true);
          expect(await f.db.select(f.db.events).get(), hasLength(2));
        });
      }

      test('vínculo directo incluso inactivo bloquea', () async {
        final id = await f.create();
        await f.variant(id, active: false);
        await expectLater(
          f.remove(id),
          throwsA(isA<InventoryProjectionConflict>()),
        );
      });

      test('componente de receta bloquea', () async {
        final id = await f.create();
        await f.variant(null);
        await f.db
            .into(f.db.recipeComponents)
            .insert(
              RecipeComponentsCompanion.insert(
                variantId: 'variant',
                inventoryItemId: id,
                quantityAtomic: 1,
              ),
            );
        await expectLater(
          f.remove(id),
          throwsA(isA<InventoryProjectionConflict>()),
        );
      });

      test(
        'venta borrador bloquea, histórica confirmada permite baja',
        () async {
          final id = await f.create();
          await f.variant(null);
          final now = DateTime.now();
          await f.db
              .into(f.db.sales)
              .insert(
                SalesCompanion.insert(
                  id: 'sale',
                  userId: 'user',
                  deviceId: 'device',
                  totalMinor: 100,
                  createdAtLocal: now,
                  updatedAtLocal: now,
                ),
              );
          await f.db
              .into(f.db.saleItems)
              .insert(
                SaleItemsCompanion.insert(
                  id: 'line',
                  saleId: 'sale',
                  variantId: 'variant',
                  consumptionConfigurationKey: Value(jsonEncode([id])),
                  productNameSnapshot: 'Producto',
                  saleModeSnapshot: 'unit',
                  quantity: const Value(1),
                  unitPriceMinor: 100,
                  totalMinor: 100,
                  sortOrder: 0,
                ),
              );
          await expectLater(
            f.remove(id),
            throwsA(isA<InventoryProjectionConflict>()),
          );
          await f.db
              .update(f.db.sales)
              .write(const SalesCompanion(status: Value('confirmada')));
          await f.remove(id);
          expect(await f.db.select(f.db.saleItems).get(), hasLength(1));
        },
      );
    });
  }

  group('server_sync', () {
    late _Fixture f;
    setUp(() => f = _Fixture(AppMode.serverSync));
    tearDown(() => f.db.close());

    test(
      'revalida edición previa y baja optimista sin confundir inactividad con conflicto',
      () async {
        final id = await f.create();
        await f.service.editarRecurso(
          EditarRecursoInventarioCommand(
            inventoryItemId: id,
            nombre: 'Nuevo nombre',
          ),
        );
        await f.remove(id);
        for (final event in await f.persistence.pendingEvents()) {
          expect(await f.validator.validate(event, {}), isNull);
        }
      },
    );

    for (final status in ['rejected', 'conflict']) {
      test('push $status restaura baja y espera creación pendiente', () async {
        final id = await f.create();
        await f.remove(id);
        var count = 0;
        final push = SyncPushService(
          syncPersistence: f.persistence,
          endpointConfig: SyncEndpointConfig(),
          conflictProjectionCleaner: f.cleaner,
          client: MockClient((request) async {
            final events = (jsonDecode(request.body) as Map)['events'] as List;
            expect(events, hasLength(1));
            count++;
            final event = events.single as Map;
            expect(
              event['event_type'],
              count == 1
                  ? 'recurso_inventario_creado'
                  : RecursoInventarioEliminadoPayload.eventType,
            );
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'event_id': event['event_id'],
                    'status': count == 1 ? 'accepted' : status,
                    'server_sequence': count,
                    'created_at_server': '2026-11-08T00:00:00.000Z',
                    'reason': 'Bloqueo servidor',
                  },
                ],
              }),
              200,
            );
          }),
        );
        await push.pushPendingEvents();
        expect((await f.projection.findItemById(id))!.active, false);
        await push.pushPendingEvents();
        expect(count, 2);
        expect((await f.projection.findItemById(id))!.active, true);
        expect((await f.deletion()).deliveryStatus, status);
      });
    }

    test(
      'conflicto restaura base y conserva el eco posterior del alta',
      () async {
        final id = await f.create();
        final before = (await f.projection.findItemById(id))!;
        await f.remove(id);
        final event = await f.deletion();
        await f.projection.advanceCreationServerSequence(
          inventoryItemId: id,
          eventId: before.createdEventId!,
          serverSequence: 9,
        );
        await f.validator.restore(event, const PendingConflict('rechazado'));
        final restored = (await f.projection.findItemById(id))!;
        expect(restored.active, true);
        expect(restored.lastEventId, before.lastEventId);
        expect(restored.version, before.version);
        expect(restored.lastServerSequence, 9);
        await f.validator.restore(event, const PendingConflict('repetido'));
        expect((await f.projection.findItemById(id))!.version, before.version);
      },
    );

    test(
      'pull aplica aceptación oficial de una baja previamente restaurada',
      () async {
        final id = await f.create();
        await f.remove(id);
        final deletion = await f.deletion();
        await f.cleaner.hideConflictProjection(deletion);
        await f.persistence.updateEventSyncStatus(deletion.eventId, 'conflict');
        expect((await f.projection.findItemById(id))!.active, true);
        await DriftSyncedEventStore(db: f.db).applySyncedEvents(
          [deletion.copyWith(serverSequence: 2)],
          applyEvent: f.handler.applyRecursoInventarioEliminado,
          acknowledgeEcho: (_) async =>
              fail('Una baja restaurada requiere reaplicación.'),
          prepareEvent: f.preparer.prepare,
        );
        expect((await f.projection.findItemById(id))!.active, false);
        expect((await f.projection.findItemById(id))!.lastServerSequence, 2);
        expect((await f.deletion()).deliveryStatus, 'delivered');
      },
    );

    test(
      'otro dispositivo reconstruye la baja oficial; eco no incrementa versión',
      () async {
        final id = await f.create();
        final creation = (await f.persistence.pendingEvents()).single;
        await f.remove(id);
        final deletion = await f.deletion();
        final other = _Fixture(AppMode.serverSync);
        try {
          await other.handler.applyRecursoInventarioCreado(
            creation.copyWith(serverSequence: 1),
          );
          await other.handler.applyRecursoInventarioEliminado(
            deletion.copyWith(serverSequence: 2),
          );
          await other.handler.applyRecursoInventarioEliminado(
            deletion.copyWith(serverSequence: 2),
          );
          expect((await other.projection.findItemById(id))!.active, false);
          expect((await other.projection.findItemById(id))!.version, 2);
          expect(
            (await other.projection.findItemById(id))!.lastServerSequence,
            2,
          );
          expect(await other.db.inventoryDao.watchRecursos().first, isEmpty);
        } finally {
          await other.db.close();
        }
      },
    );

    test(
      'artículo oficial restaura baja pendiente antes de validar su vínculo',
      () async {
        final id = await f.create();
        await f.remove(id);
        final payload = ProductoCreadoPayload.create(
          nombre: 'Producto oficial',
          categoriaId: null,
          saleConfiguration: const UnitSaleConfiguration(),
          variantes: [
            ProductoCreadoVariante.create(
              id: '60000000-0000-4000-8000-000000000001',
              nombre: null,
              precioVentaMenor: 100,
              costoEstandarMenor: null,
              inventoryItemId: id,
              orden: 0,
            ),
          ],
          dependenciasInventario: [
            ProductoCreadoInventarioDependencia(refId: id),
          ],
        );
        final official = SyncEvent(
          eventId: '50000000-0000-4000-8000-000000000001',
          aggregateType: 'product',
          aggregateId: '70000000-0000-4000-8000-000000000001',
          eventType: ProductoCreadoPayload.eventType,
          deviceId: 'other',
          userId: 'user',
          createdAtLocal: DateTime.now(),
          serverSequence: 5,
          baseVersion: 1,
          payload: payload.toJson(),
        );
        await f.preparer.prepare(official);
        await ProductoEventHandler(
          DriftProductoProjectionStore(productoDao: f.db.productoDao),
          variantInventoryMemoryStore: DriftVariantInventoryMemoryStore(
            dao: f.db.variantInventoryMemoryDao,
          ),
          inventoryProjectionStore: f.projection,
        ).applyProductoCreado(official);
        expect((await f.projection.findItemById(id))!.active, true);
        expect(
          (await f.db.select(f.db.productVariants).get())
              .single
              .inventoryItemId,
          id,
        );
        expect((await f.deletion()).deliveryStatus, 'conflict');
      },
    );

    test(
      'pull concurrente revierte baja antes de aplicar movimiento oficial',
      () async {
        final id = await f.create();
        final before = (await f.projection.findItemById(id))!;
        await f.remove(id);
        final official = SyncEvent(
          eventId: 'official',
          aggregateType: 'inventory_item',
          aggregateId: id,
          eventType: 'movimiento_inventario_registrado',
          deviceId: 'other',
          userId: 'user',
          createdAtLocal: DateTime.now(),
          baseVersion: before.version,
          serverSequence: 5,
          payload: {
            'base_event_id': before.lastEventId,
            'movement': {
              'movement_id': '30000000-0000-4000-8000-000000000001',
              'movement_type': 'stock_receipt',
              'quantity_delta_atomic': 2,
              'reason': null,
              'reversal_of_movement_id': null,
            },
          },
        );
        await f.preparer.prepare(official);
        await f.handler.applyMovimientoInventarioRegistrado(official);
        expect((await f.projection.findItemById(id))!.active, true);
        expect(
          (await f.projection.findBalanceByItemId(id))!.quantityOnHandAtomic,
          2,
        );
        expect((await f.deletion()).deliveryStatus, 'conflict');
      },
    );
  });

  test('contrato rechaza campos adicionales y base vacía', () {
    for (final payload in <Map<String, Object?>>[
      {},
      {'base_event_id': ''},
      {'base_event_id': 'base', 'force': true},
    ]) {
      expect(
        () => RecursoInventarioEliminadoPayload.fromJson(payload),
        throwsFormatException,
      );
    }
    expect(
      RecursoInventarioEliminadoPayload.create(baseEventId: ' base ').toJson(),
      {'base_event_id': 'base'},
    );
  });
}

class _Fixture {
  _Fixture(AppMode mode) {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    projection = DriftInventoryProjectionStore(
      inventoryDao: db.inventoryDao,
      unitDao: db.unitDao,
    );
    tracking = DriftVariantInventoryTrackingStore(
      inventoryDao: db.inventoryDao,
      productoDao: db.productoDao,
    );
    handler = InventoryEventHandler(projection, trackingStore: tracking);
    store = DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      eventProcessor: EventProcessor(handlers: inventoryEventHandlers(handler)),
      appConfigController: AppConfigController(
        AppConfig.initial.copyWith(mode: mode, setupCompleted: true),
      ),
    );
    service = InventoryCommandService(
      eventStore: store,
      commandContext: const LocalCommandContext(
        deviceId: 'device',
        userId: 'user',
      ),
      inventoryProjectionStore: projection,
      trackingStore: tracking,
    );
    persistence = DriftSyncPersistence(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      syncCheckpointDao: db.syncCheckpointDao,
    );
    validator = InventoryPendingEventValidator(
      inventoryProjectionStore: projection,
      syncedEventHistory: persistence,
      dependencies: PendingEventDependencyResolver(persistence),
      trackingStore: tracking,
    );
    final category = DriftCategoriaProjectionStore(
      categoriaDao: db.categoriaDao,
    );
    cleaner = SyncConflictProjectionCleaner(
      espacioProjectionStore: DriftEspacioProjectionStore(
        espacioDao: db.espacioDao,
      ),
      categoriaProjectionStore: category,
      inventoryProjectionStore: projection,
      categoriaConflictProjectionRestorer: CategoriaConflictProjectionRestorer(
        category,
      ),
      categoriaMovidaConflictProjectionRestorer:
          CategoriaMovidaConflictProjectionRestorer(category),
    );
    preparer = RemoteEventPreparer(
      syncPersistence: persistence,
      categoriaEliminadaConflictProjectionRestorer:
          CategoriaEliminadaConflictProjectionRestorer(category),
      conflictProjectionCleaner: cleaner,
    );
  }
  late final AppDatabase db;
  late final DriftInventoryProjectionStore projection;
  late final DriftVariantInventoryTrackingStore tracking;
  late final InventoryEventHandler handler;
  late final DriftLocalEventStore store;
  late final InventoryCommandService service;
  late final DriftSyncPersistence persistence;
  late final InventoryPendingEventValidator validator;
  late final SyncConflictProjectionCleaner cleaner;
  late final RemoteEventPreparer preparer;
  Future<String> create() async {
    await service.crearRecurso(
      const CrearRecursoInventarioCommand(
        nombre: 'Harina',
        defaultUnitId: InventoryUnitIds.piece,
      ),
    );
    return (await db.select(db.inventoryItems).get()).single.id;
  }

  Future<void> remove(String id) => service.eliminarRecurso(
    EliminarRecursoInventarioCommand(inventoryItemId: id),
  );
  Future<SyncEvent> deletion() async => (await persistence.eventById(
    (await db.select(db.events).get())
        .singleWhere(
          (e) => e.eventType == RecursoInventarioEliminadoPayload.eventType,
        )
        .eventId,
  ))!;
  Future<void> variant(String? resourceId, {bool active = true}) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'product', name: 'Producto'));
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: 'variant',
            productId: 'product',
            salePriceMinor: 100,
            inventoryItemId: Value(resourceId),
            active: Value(active),
            sortOrder: 0,
          ),
        );
  }
}
