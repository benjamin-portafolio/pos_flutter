import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_confirmada_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/application/sync/revalidation/sale_pending_event_validator.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

const productId = '00000000-0000-4000-8000-000000000001';
const variantId = '00000000-0000-4000-8000-000000000002';
const itemId = '00000000-0000-4000-8000-000000000003';
const configId = '00000000-0000-4000-8000-000000000004';
const resourceId = '00000000-0000-4000-8000-000000000005';
void main() {
  late AppDatabase db;
  late AppConfigController config;
  late Directory directory;
  bool failAfterApply = false;
  final context = const LocalCommandContext(userId: 'user', deviceId: 'tablet');
  DriftConfirmedSaleStore getStore() => DriftConfirmedSaleStore(db);
  DriftSyncPersistence persistence() => DriftSyncPersistence(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    syncCheckpointDao: db.syncCheckpointDao,
  );
  DriftLocalEventStore events() => DriftLocalEventStore(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    appConfigController: config,
    eventProcessor: EventProcessor(
      handlers: {
        ProductoAgregadoBorradorPayload.eventType: VentaBorradorEventHandler(
          db.saleDao,
        ).apply,
        VentaConfirmadaPayload.eventType: (e) async {
          await VentaConfirmadaEventHandler(getStore()).apply(e);
          if (failAfterApply) throw StateError('injected');
        },
      },
    ),
  );
  SyncPushService push(http.Client client) {
    final categories = DriftCategoriaProjectionStore(
      categoriaDao: db.categoriaDao,
    );
    return SyncPushService(
      syncPersistence: persistence(),
      endpointConfig: SyncEndpointConfig(initialBaseUrl: 'http://test'),
      client: client,
      conflictProjectionCleaner: SyncConflictProjectionCleaner(
        espacioProjectionStore: DriftEspacioProjectionStore(
          espacioDao: db.espacioDao,
        ),
        categoriaProjectionStore: categories,
        categoriaConflictProjectionRestorer:
            CategoriaConflictProjectionRestorer(categories),
        categoriaMovidaConflictProjectionRestorer:
            CategoriaMovidaConflictProjectionRestorer(categories),
        productoProjectionStore: DriftProductoProjectionStore(
          productoDao: db.productoDao,
        ),
        inventoryProjectionStore: DriftInventoryProjectionStore(
          inventoryDao: db.inventoryDao,
          unitDao: db.unitDao,
        ),
      ),
    );
  }

  VentaBorradorCommandService draft() => VentaBorradorCommandService(
    store: db.saleDao,
    products: DriftProductoProjectionStore(productoDao: db.productoDao),
    units: UnidadInventarioRepositoryImpl(unitDao: db.unitDao),
    events: events(),
    context: context,
  );
  VentaCommandService service() => VentaCommandService(
    drafts: db.saleDao,
    products: DriftProductoProjectionStore(productoDao: db.productoDao),
    inventory: DriftInventoryProjectionStore(
      inventoryDao: db.inventoryDao,
      unitDao: db.unitDao,
    ),
    events: events(),
    context: context,
  );
  Future<ConfirmarVentaCommand> command({int? received}) async {
    final d = (await db.saleDao.findDraft('user', 'tablet'))!;
    return ConfirmarVentaCommand(
      saleId: d.id,
      expectedDraftEventId: d.lastEventId!,
      expectedTotalMinor: d.totalMinor,
      receivedMinor: received,
    );
  }

  Future<void> seed({String mode = 'direct', bool measured = false}) async {
    await db
        .into(db.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            id: itemId,
            name: 'Recurso',
            defaultUnitId: measured
                ? InventoryUnitIds.gram
                : InventoryUnitIds.piece,
            createdEventId: const Value(resourceId),
            lastEventId: const Value(resourceId),
          ),
        );
    await db
        .into(db.inventoryBalances)
        .insert(
          InventoryBalancesCompanion.insert(
            inventoryItemId: itemId,
            quantityOnHandAtomic: 0,
            quantityAvailableAtomic: 0,
            lastEventId: resourceId,
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: productId,
            name: 'Café',
            saleMode: Value(measured ? 'measured' : 'unit'),
            saleUnitId: Value(measured ? InventoryUnitIds.gram : null),
            priceReferenceQuantityAtomic: Value(measured ? 2 : null),
            createdEventId: const Value(configId),
            lastEventId: const Value(configId),
          ),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: variantId,
            productId: productId,
            salePriceMinor: 10000,
            standardCostMinor: const Value(900),
            inventoryItemId: Value(mode == 'direct' ? itemId : null),
            sortOrder: 0,
            createdEventId: const Value(configId),
            lastEventId: const Value(configId),
          ),
        );
    if (mode == 'recipe') {
      await db
          .into(db.recipeComponents)
          .insert(
            RecipeComponentsCompanion.insert(
              variantId: variantId,
              inventoryItemId: itemId,
              quantityAtomic: 3,
            ),
          );
    }
    for (final id in [configId, resourceId]) {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              eventId: id,
              aggregateType: id == configId ? 'product' : 'inventory_item',
              aggregateId: id == configId ? productId : itemId,
              eventType: id == configId
                  ? 'producto_creado'
                  : 'recurso_inventario_creado',
              deviceId: 'tablet',
              userId: 'user',
              createdAtLocal: DateTime.now(),
              payload: '{}',
              deliveryStatus: const Value('delivered'),
            ),
          );
    }
  }

  Future<void> add({bool measured = false}) => draft().agregar(
    AgregarProductoBorradorCommand(
      variantId: variantId,
      measuredQuantity: measured ? '1' : null,
      expectedUnitId: measured ? InventoryUnitIds.gram : null,
    ),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cash_test_');
    db = AppDatabase.forTesting(
      NativeDatabase(File('${directory.path}/test.sqlite')),
    );
    config = AppConfigController(
      AppConfig.initial.copyWith(mode: AppMode.serverSync),
    );
    failAfterApply = false;
  });
  tearDown(() async {
    await db.close();
    config.dispose();
    await directory.delete(recursive: true);
  });
  for (final mode in AppMode.values) {
    for (final received in <int?>[null, 10000, 20000]) {
      test(
        '${mode.name}: efectivo $received, commit completo y reintento persistente',
        () async {
          config.dispose();
          config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
          await seed();
          await add();
          final c = await command(received: received);
          await service().confirmar(c);
          final payment = (await db.select(db.salePayments).get()).single;
          expect(payment.amountMinor, 10000);
          expect(payment.receivedMinor, received ?? 10000);
          expect(payment.changeMinor, (received ?? 10000) - 10000);
          expect(
            (await db.select(db.inventoryBalances).get())
                .single
                .quantityOnHandAtomic,
            -1,
          );
          expect(
            (await db.select(db.inventoryMovements).get())
                .single
                .totalCostMinor,
            isNull,
          );
          final confirmed = (await getStore().watchConfirmed().first).single;
          expect(
            confirmed.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          if (mode == AppMode.standalone) {
            expect(await db.select(db.eventRefs).get(), isEmpty);
          }
          await expectLater(service().confirmar(c), throwsStateError);
          await add();
          expect(await db.select(db.sales).get(), hasLength(2));
        },
      );
    }
  }
  for (final mode in ['none', 'direct', 'recipe']) {
    for (final measured in [false, true]) {
      test(
        '$mode measured=$measured conserva consumo histórico y half-up',
        () async {
          await seed(mode: mode, measured: measured);
          await add(measured: measured);
          await service().confirmar(await command());
          final movements = await db.select(db.inventoryMovements).get();
          expect(movements, mode == 'none' ? isEmpty : hasLength(1));
          if (mode != 'none') {
            expect(
              movements.single.quantityDeltaAtomic,
              mode == 'direct'
                  ? -1
                  : measured
                  ? -2
                  : -3,
            );
          }
          expect(
            (await db.select(db.salePayments).get()).single.amountMinor,
            measured ? 5000 : 10000,
          );
        },
      );
    }
  }
  test(
    'insuficiente, límites, vacío y borrador modificado conservan borrador',
    () async {
      await seed();
      await add();
      final c = await command();
      await expectLater(
        service().confirmar(await command(received: 9999)),
        throwsFormatException,
      );
      await expectLater(
        service().confirmar(await command(received: 9007199254740992)),
        throwsFormatException,
      );
      await add();
      await expectLater(service().confirmar(c), throwsStateError);
      await (db.delete(db.saleItems)).go();
      await expectLater(
        service().confirmar(await command()),
        throwsFormatException,
      );
      expect(await db.select(db.salePayments).get(), isEmpty);
    },
  );
  test('doble toque solo crea un pago', () async {
    await seed();
    await add();
    final c = await command();
    final results = await Future.wait([
      service().confirmar(c).then((_) => true).catchError((_) => false),
      service().confirmar(c).then((_) => true).catchError((_) => false),
    ]);
    expect(results.where((r) => r).length, 1);
    expect(await db.select(db.salePayments).get(), hasLength(1));
  });
  test(
    'fallo después de movimientos revierte evento, pago, saldo y conserva borrador',
    () async {
      await seed();
      await add();
      final before = await db.select(db.events).get();
      failAfterApply = true;
      await expectLater(service().confirmar(await command()), throwsStateError);
      expect(await db.select(db.events).get(), hasLength(before.length));
      expect(await db.select(db.salePayments).get(), isEmpty);
      expect(await db.select(db.inventoryMovements).get(), isEmpty);
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        0,
      );
      expect((await db.select(db.sales).get()).single.status, 'borrador');
    },
  );
  test(
    'reinicio offline, reconocimiento de push y pull propio sin doble consumo',
    () async {
      await seed();
      await add();
      await service().confirmar(await command());
      final original = (await getStore().watchConfirmed().first).single;
      await db.close();
      db = AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/test.sqlite')),
      );
      expect(
        (await persistence().pendingEvents()).single.eventId,
        original.eventId,
      );
      final official = original.copyWith(
        serverSequence: 30,
        deliveryStatus: 'delivered',
        baseVersion: 1,
      );
      await persistence().updateEventSyncStatus(
        original.eventId,
        'delivered',
        serverSequence: 30,
      );
      var applied = 0;
      await DriftSyncedEventStore(db: db).applySyncedEvents(
        [official],
        applyEvent: (e) async {
          applied++;
          await VentaConfirmadaEventHandler(getStore()).apply(e);
        },
        acknowledgeEcho: (e) =>
            getStore().acknowledge(e.eventId, e.serverSequence!),
      );
      expect(applied, 0);
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -1,
      );
      expect(
        (await db.select(db.salePayments).get()).single.lastServerSequence,
        30,
      );
      expect(
        (await db.select(db.inventoryMovements).get()).single.serverSequence,
        30,
      );
    },
  );
  test(
    'pull otro dispositivo crea venta autocontenida y deduplica sale_id',
    () async {
      await seed();
      await add();
      await service().confirmar(await command());
      final e = (await getStore().watchConfirmed().first).single.copyWith(
        baseVersion: 1,
        serverSequence: 12,
        deliveryStatus: 'delivered',
      );
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seed();
      await DriftSyncedEventStore(db: db).applySyncedEvents(
        [e],
        applyEvent: VentaConfirmadaEventHandler(getStore()).apply,
        acknowledgeEcho: (e) =>
            getStore().acknowledge(e.eventId, e.serverSequence!),
      );
      expect((await db.select(db.sales).get()).single.status, 'confirmada');
      await expectLater(
        VentaConfirmadaEventHandler(
          getStore(),
        ).apply(e.copyWith(eventId: resourceId)),
        throwsStateError,
      );
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -1,
      );
    },
  );
  test(
    'standalone: cobro y arranque no instancian monitor ni producen tráfico sync',
    () async {
      config.dispose();
      config = AppConfigController(
        AppConfig.initial.copyWith(
          mode: AppMode.standalone,
          setupCompleted: true,
          backupProvider: BackupProvider.none,
        ),
      );
      var syncInstantiations = 0;
      getIt.registerLazySingleton<SyncAvailabilityMonitor>(() {
        syncInstantiations++;
        throw StateError(
          'No debe arrancar health, push, pull, preflight ni WebSocket.',
        );
      });
      try {
        await startConfiguredRuntimeServices(config.config);
        await seed();
        await add();
        await service().confirmar(await command());
        expect(syncInstantiations, 0);
        expect(await persistence().pendingEvents(), isEmpty);
        expect(await db.select(db.eventRefs).get(), isEmpty);
      } finally {
        await getIt.unregister<SyncAvailabilityMonitor>();
      }
    },
  );
  test(
    'push espera dependencia en otro lote y respuesta perdida reintenta IDs estables',
    () async {
      await seed();
      await add();
      await service().confirmar(await command());
      final e = (await getStore().watchConfirmed().first).single;
      final state = await DriftProductoProjectionStore(
        productoDao: db.productoDao,
      ).snapshot(productId);
      await (db.update(
        db.events,
      )..where((e) => e.eventId.equals(configId))).write(
        EventsCompanion(
          payload: Value(jsonEncode(state.toJson())),
          deliveryStatus: const Value('pending'),
        ),
      );
      var calls = 0;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final batch = body['events'] as List;
        calls++;
        expect(batch, hasLength(1));
        final id = (batch.single as Map)['event_id'];
        expect(id, calls == 1 ? configId : e.eventId);
        if (calls == 2) throw const SocketException('Respuesta perdida');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'event_id': id,
                'status': calls == 3 ? 'duplicate' : 'accepted',
                'original_sync_status': 'synced',
                'server_sequence': calls == 1 ? 1 : 2,
              },
            ],
          }),
          200,
        );
      });
      final sender = push(client);
      expect((await sender.pushPendingEvents()).pending, 1);
      await expectLater(sender.pushPendingEvents(), throwsA(isA<Exception>()));
      expect((await persistence().pendingEvents()).single.eventId, e.eventId);
      expect((await sender.pushPendingEvents()).synced, 1);
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -1,
      );
      expect(
        (await db.select(db.salePayments).get()).single.lastServerSequence,
        2,
      );
      client.close();
    },
  );
  for (final status in ['conflict', 'rejected']) {
    test('push $status deja visibles pago y consumo', () async {
      await seed();
      await add();
      await service().confirmar(await command());
      final e = (await getStore().watchConfirmed().first).single;
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'results': [
              {
                'event_id': e.eventId,
                'status': 'duplicate',
                'original_sync_status': status,
                'server_sequence': 9,
                'reason': 'Incidencia',
              },
            ],
          }),
          200,
        ),
      );
      await push(client).pushPendingEvents();
      expect(
        (await getStore().watchConfirmed().first).single.deliveryStatus,
        status,
      );
      expect(
        (await db.select(db.salePayments).get()).single.amountMinor,
        10000,
      );
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -1,
      );
      client.close();
    });
  }
  test(
    'limpieza de dependencias en conflicto no elimina cobro ni referencias',
    () async {
      await seed();
      await add();
      await service().confirmar(await command());
      await db.productoDao.eliminarProductoCreadoPorEvento(configId);
      await db.inventoryDao.eliminarCreacionPorEvento(resourceId);
      expect((await db.select(db.sales).get()).single.status, 'confirmada');
      expect(
        (await db.select(db.productVariants).get()).single.active,
        isFalse,
      );
      expect((await db.select(db.inventoryItems).get()).single.active, isFalse);
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -1,
      );
    },
  );
  test(
    'receta conocida cambió antes del cobro: revisión sin perder borrador',
    () async {
      await seed(mode: 'recipe');
      await add();
      final c = await command();
      await db
          .update(db.recipeComponents)
          .write(const RecipeComponentsCompanion(quantityAtomic: Value(9)));
      await expectLater(service().confirmar(c), throwsStateError);
      expect((await db.select(db.sales).get()).single.status, 'borrador');
      expect(await db.select(db.salePayments).get(), isEmpty);
    },
  );
  test(
    'un consumo redondeado a cero conserva configuración sin movimiento',
    () async {
      await seed(mode: 'recipe', measured: true);
      await db
          .update(db.products)
          .write(
            const ProductsCompanion(priceReferenceQuantityAtomic: Value(10)),
          );
      await add(measured: true);
      await service().confirmar(await command());
      expect(await db.select(db.inventoryMovements).get(), isEmpty);
      final p = VentaConfirmadaPayload.fromJson(
        (await getStore().watchConfirmed().first).single.payload,
      );
      expect(p.lines.single.consumptions.single.componentAtomic, 3);
      expect(p.lines.single.consumptions.single.movementId, isNull);
      await db.productoDao.eliminarProductoCreadoPorEvento(configId);
      await db.inventoryDao.eliminarCreacionPorEvento(resourceId);
      expect((await db.select(db.inventoryItems).get()).single.active, isFalse);
      expect((await db.select(db.salePayments).get()).single.amountMinor, 1000);
    },
  );
  test(
    'precio capturado se conserva; desactivación conocida exige revisión',
    () async {
      await seed();
      await add();
      await db
          .update(db.productVariants)
          .write(const ProductVariantsCompanion(salePriceMinor: Value(50000)));
      await service().confirmar(await command());
      expect(
        (await db.select(db.salePayments).get()).single.amountMinor,
        10000,
      );
      await add();
      await db
          .update(db.productVariants)
          .write(const ProductVariantsCompanion(active: Value(false)));
      await expectLater(service().confirmar(await command()), throwsStateError);
      expect(
        (await db.select(db.sales).get()).where((s) => s.status == 'borrador'),
        hasLength(1),
      );
    },
  );
  test(
    'dependencias pendientes/irresolubles y rechazo conservan cobro y consumo',
    () async {
      await seed();
      await add();
      await service().confirmar(await command());
      final e = (await getStore().watchConfirmed().first).single;
      await persistence().updateEventSyncStatus(configId, 'pending');
      final validator = SalePendingEventValidator(persistence());
      expect(await validator.validate(e, {}), isNull);
      await persistence().updateEventSyncStatus(configId, 'rejected');
      final conflict = await validator.validate(e, {});
      expect(conflict, isNotNull);
      await validator.restore(e, conflict!);
      await persistence().updateEventSyncStatus(
        e.eventId,
        'rejected',
        rejectionReason: 'dependencia',
      );
      expect(
        (await getStore().watchConfirmed().first).single.deliveryStatus,
        'rejected',
      );
      expect((await db.select(db.sales).get()).single.status, 'confirmada');
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -1,
      );
      expect(
        VentaConfirmadaPayload.fromJson(
          Map<String, Object?>.from(
            jsonDecode((await db.select(db.events).get()).last.payload) as Map,
          ),
        ).lines,
        hasLength(1),
      );
    },
  );
}
