import 'package:uuid/uuid.dart';
import 'package:pos_flutter/data/repositories/collection_repository_impl.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/application/commands/clientes/cliente_command_service.dart';
import 'package:pos_flutter/application/commands/clientes/crear_cliente_command.dart';
import 'package:pos_flutter/application/commands/creditos/credito_command_service.dart';
import 'package:pos_flutter/application/commands/creditos/registrar_abono_command.dart';
import 'package:pos_flutter/application/sync/handlers/cliente_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/abono_cliente_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/cliente_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/abono_cliente_registrado_payload.dart';
import 'package:pos_flutter/data/local/drift/drift_cliente_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_customer_credit_store.dart';
import 'package:pos_flutter/data/repositories/customer_account_repository_impl.dart';
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
        ClienteCreadoPayload.eventType: ClienteEventHandler(
          DriftClienteProjectionStore(db.clienteDao),
        ).apply,
        AbonoClienteRegistradoPayload.eventType: AbonoClienteEventHandler(
          DriftCustomerCreditStore(db),
        ).apply,
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
    clientes: DriftClienteProjectionStore(db.clienteDao),
    drafts: db.saleDao,
    products: DriftProductoProjectionStore(productoDao: db.productoDao),
    inventory: DriftInventoryProjectionStore(
      inventoryDao: db.inventoryDao,
      unitDao: db.unitDao,
    ),
    events: events(),
    context: context,
  );
  Future<ConfirmarVentaCommand> command({
    int? received,
    String method = 'cash',
    String? reference,
  }) async {
    final d = (await db.saleDao.findDraft('user', 'tablet'))!;
    return ConfirmarVentaCommand(
      saleId: d.id,
      expectedDraftEventId: d.lastEventId!,
      expectedTotalMinor: d.totalMinor,
      receivedMinor: received,
      paymentMethod: method,
      paymentReference: reference,
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
  for (final method in ['cash', 'transfer']) {
    group('$method: atomicidad, reinicio y sincronización', () {
      test('doble toque solo crea un pago', () async {
        await seed();
        await add();
        final c = await command(
          method: method,
          reference: method == 'transfer' ? '  BANK-42  ' : null,
        );
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
          await expectLater(
            service().confirmar(
              await command(
                method: method,
                reference: method == 'transfer' ? '  BANK-42  ' : null,
              ),
            ),
            throwsStateError,
          );
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
          await service().confirmar(
            await command(
              method: method,
              reference: method == 'transfer' ? '  BANK-42  ' : null,
            ),
          );
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
            (await db.select(db.inventoryMovements).get())
                .single
                .serverSequence,
            30,
          );
        },
      );
      test(
        'pull otro dispositivo crea venta autocontenida y deduplica sale_id',
        () async {
          await seed();
          await add();
          await service().confirmar(
            await command(
              method: method,
              reference: method == 'transfer' ? '  BANK-42  ' : null,
            ),
          );
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
            await service().confirmar(
              await command(
                method: method,
                reference: method == 'transfer' ? '  BANK-42  ' : null,
              ),
            );
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
          await service().confirmar(
            await command(
              method: method,
              reference: method == 'transfer' ? '  BANK-42  ' : null,
            ),
          );
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
            if (calls > 1) {
              expect(
                (batch.single as Map)['payload']['payment_method'],
                method,
              );
              expect(
                (batch.single as Map)['payload']['payment_reference'],
                method == 'transfer' ? 'BANK-42' : null,
              );
            }
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
          await expectLater(
            sender.pushPendingEvents(),
            throwsA(isA<Exception>()),
          );
          expect(
            (await persistence().pendingEvents()).single.eventId,
            e.eventId,
          );
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
          await service().confirmar(
            await command(
              method: method,
              reference: method == 'transfer' ? '  BANK-42  ' : null,
            ),
          );
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
  Future<void> createCustomer() => ClienteCommandService(
    clienteProjectionStore: DriftClienteProjectionStore(db.clienteDao),
    eventStore: events(),
    commandContext: context,
  ).crearCliente(const CrearClienteCommand(nombre: 'Ana', telefono: '555'));
  CreditoCommandService creditService() => CreditoCommandService(
    store: DriftCustomerCreditStore(db),
    clientes: DriftClienteProjectionStore(db.clienteDao),
    events: events(),
    context: context,
  );
  Future<String> creditSale(String clienteId, int amount) async {
    await db
        .update(db.productVariants)
        .write(ProductVariantsCompanion(salePriceMinor: Value(amount)));
    await add();
    final c = await command();
    await service().confirmar(
      ConfirmarVentaCommand(
        saleId: c.saleId,
        expectedDraftEventId: c.expectedDraftEventId,
        expectedTotalMinor: c.expectedTotalMinor,
        clienteId: clienteId,
        paymentMethod: 'credit',
      ),
    );
    return c.saleId;
  }

  for (final mode in AppMode.values) {
    test('${mode.name}: crédito FIFO, anticipos, reinicio y refs', () async {
      config.dispose();
      config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
      await seed();
      await createCustomer();
      final clienteId = (await db.select(db.clientes).get()).single.id;
      final first = await creditSale(clienteId, 2000);
      Future<String> pay(int amount) async {
        final id = const Uuid().v4();
        await creditService().registrarAbono(
          RegistrarAbonoCommand(
            id: id,
            clienteId: clienteId,
            amountMinor: amount,
            method: 'cash',
          ),
        );
        return id;
      }

      await pay(1000);
      final second = await creditSale(clienteId, 5000);
      await pay(500);
      var account = await CustomerAccountRepositoryImpl(
        db,
      ).watchAccount(clienteId).first;
      expect(account.balanceMinor, BigInt.from(-5500));
      expect(
        account.pendingMinor(account.entries.singleWhere((e) => e.id == first)),
        500,
      );
      final lastPayment = await pay(1000);
      account = await CustomerAccountRepositoryImpl(
        db,
      ).watchAccount(clienteId).first;
      expect(
        account.pendingMinor(account.entries.singleWhere((e) => e.id == first)),
        0,
      );
      expect(
        account.pendingMinor(
          account.entries.singleWhere((e) => e.id == second),
        ),
        4500,
      );
      final split = (await db.select(db.creditAllocations).get())
          .where((a) => a.paymentId == lastPayment)
          .toList();
      expect(split.map((a) => a.amountMinor), [500, 500]);
      expect(await db.select(db.salePayments).get(), isEmpty);
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -2,
      );
      await pay(6000);
      final third = await creditSale(clienteId, 1000);
      account = await CustomerAccountRepositoryImpl(
        db,
      ).watchAccount(clienteId).first;
      expect(account.balanceMinor, BigInt.from(500));
      expect(
        account.pendingMinor(account.entries.singleWhere((e) => e.id == third)),
        0,
      );
      final paymentEvents =
          await (db.select(db.events)..where(
                (e) =>
                    e.eventType.equals(AbonoClienteRegistradoPayload.eventType),
              ))
              .get();
      expect(
        paymentEvents.every(
          (e) =>
              e.deliveryStatus ==
              (mode == AppMode.standalone ? 'not_required' : 'pending'),
        ),
        isTrue,
      );
      expect(
        await db.select(db.eventRefs).get(),
        mode == AppMode.standalone ? isEmpty : isNotEmpty,
      );
      await db.close();
      db = AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/test.sqlite')),
      );
      expect(
        (await CustomerAccountRepositoryImpl(
          db,
        ).watchAccount(clienteId).first).balanceMinor,
        BigInt.from(500),
      );
    });
  }
  test(
    'abono: doble envío con mismo id es idempotente, otro importe se rechaza',
    () async {
      await createCustomer();
      final cliente = (await db.select(db.clientes).get()).single;
      final c = RegistrarAbonoCommand(
        id: const Uuid().v4(),
        clienteId: cliente.id,
        amountMinor: 1000,
        method: 'transfer',
        reference: '  REF  ',
      );
      final result = await Future.wait([
        creditService().registrarAbono(c),
        creditService().registrarAbono(c),
      ]);
      expect(result.toSet(), hasLength(1));
      expect(
        (await db.select(db.customerPayments).get()).single.reference,
        'REF',
      );
      await expectLater(
        creditService().registrarAbono(
          RegistrarAbonoCommand(
            id: c.id,
            clienteId: cliente.id,
            amountMinor: 2000,
            method: 'cash',
          ),
        ),
        throwsStateError,
      );
      await persistence().updateEventSyncStatus(
        result.first,
        'delivered',
        serverSequence: 90,
      );
      expect(
        (await db.select(db.customerPayments).get()).single.lastServerSequence,
        90,
      );
    },
  );
  test(
    'crédito exige cliente y no acepta efectivo; transacción conserva borrador',
    () async {
      await seed();
      await add();
      final c = await command();
      await expectLater(
        service().confirmar(
          ConfirmarVentaCommand(
            saleId: c.saleId,
            expectedDraftEventId: c.expectedDraftEventId,
            expectedTotalMinor: c.expectedTotalMinor,
            paymentMethod: 'credit',
          ),
        ),
        throwsStateError,
      );
      await createCustomer();
      final cliente = (await db.select(db.clientes).get()).single;
      await expectLater(
        service().confirmar(
          ConfirmarVentaCommand(
            saleId: c.saleId,
            expectedDraftEventId: c.expectedDraftEventId,
            expectedTotalMinor: c.expectedTotalMinor,
            clienteId: cliente.id,
            paymentMethod: 'credit',
            receivedMinor: 1,
          ),
        ),
        throwsFormatException,
      );
      failAfterApply = true;
      await expectLater(
        service().confirmar(
          ConfirmarVentaCommand(
            saleId: c.saleId,
            expectedDraftEventId: c.expectedDraftEventId,
            expectedTotalMinor: c.expectedTotalMinor,
            clienteId: cliente.id,
            paymentMethod: 'credit',
          ),
        ),
        throwsStateError,
      );
      expect(await db.select(db.creditSales).get(), isEmpty);
      expect(await db.select(db.inventoryMovements).get(), isEmpty);
      expect((await db.select(db.sales).get()).single.status, 'borrador');
    },
  );
  test(
    'pull: abono recibido antes de venta converge y los ecos no duplican',
    () async {
      await seed();
      await createCustomer();
      final cliente = (await db.select(db.clientes).get()).single;
      await creditSale(cliente.id, 2000);
      final id = const Uuid().v4();
      final paidEventId = await creditService().registrarAbono(
        RegistrarAbonoCommand(
          id: id,
          clienteId: cliente.id,
          amountMinor: 1000,
          method: 'cash',
        ),
      );
      final saleEvent = (await getStore().watchConfirmed().first).single
          .copyWith(
            baseVersion: 1,
            serverSequence: 11,
            deliveryStatus: 'delivered',
          );
      final paymentEvent = (await persistence().eventById(paidEventId))!
          .copyWith(
            baseVersion: 1,
            serverSequence: 10,
            deliveryStatus: 'delivered',
          );
      final customerEvent =
          (await persistence().eventById(cliente.createdEventId!))!.copyWith(
            baseVersion: 1,
            serverSequence: 9,
            deliveryStatus: 'delivered',
          );
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seed();
      final creditStore = DriftCustomerCreditStore(db);
      final processor = EventProcessor(
        handlers: {
          ClienteCreadoPayload.eventType: ClienteEventHandler(
            DriftClienteProjectionStore(db.clienteDao),
          ).apply,
          AbonoClienteRegistradoPayload.eventType: AbonoClienteEventHandler(
            creditStore,
          ).apply,
          VentaConfirmadaPayload.eventType: VentaConfirmadaEventHandler(
            getStore(),
          ).apply,
        },
      );
      for (final page in [
        [customerEvent, paymentEvent],
        [saleEvent],
        [paymentEvent, saleEvent],
      ]) {
        await DriftSyncedEventStore(db: db).applySyncedEvents(
          page,
          applyEvent: processor.apply,
          acknowledgeEcho: (e) =>
              getStore().acknowledge(e.eventId, e.serverSequence!),
        );
      }
      final account = await CustomerAccountRepositoryImpl(
        db,
      ).watchAccount(cliente.id).first;
      expect(account.balanceMinor, BigInt.from(-1000));
      expect(
        (await db.select(db.creditAllocations).get()).single.amountMinor,
        1000,
      );
      expect(
        (await db.select(db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -1,
      );
    },
  );
  for (final mode in AppMode.values) {
    for (final reference in <String?>[
      null,
      '',
      '   ',
      '  ABC-123  ',
      'x' * 500,
    ]) {
      test(
        'transfer $mode referencia longitud ${reference?.length}: persiste, refs y reinicio',
        () async {
          config.dispose();
          config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
          await seed();
          await add();
          await service().confirmar(
            await command(method: 'transfer', reference: reference),
          );
          final e = (await getStore().watchConfirmed().first).single;
          final p = VentaConfirmadaPayload.fromJson(e.payload);
          final expected = reference?.trim();
          expect(
            p.paymentReference,
            expected == null || expected.isEmpty ? null : expected,
          );
          expect(p.receivedMinor, 10000);
          expect(p.changeMinor, 0);
          expect(
            p
                .refs(e.aggregateId)
                .where((r) => r.refType == 'payment')
                .single
                .refId,
            p.paymentId,
          );
          expect(
            await db.select(db.eventRefs).get(),
            mode == AppMode.standalone ? isEmpty : isNotEmpty,
          );
          expect(
            e.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          await db.close();
          db = AppDatabase.forTesting(
            NativeDatabase(File('${directory.path}/test.sqlite')),
          );
          final sale = (await ConfirmedSaleRepositoryImpl(
            getStore(),
          ).watchSales().first).single;
          expect(sale.paymentMethod, 'transfer');
          expect(sale.paymentReference, p.paymentReference);
          final row = (await CollectionRepositoryImpl(
            db,
          ).watchCollections().first).single;
          expect(row.method, 'transfer');
          expect(row.reference, p.paymentReference);
          expect(row.amountMinor, 10000);
          expect(row.userId, 'user');
          expect(row.deviceId, 'tablet');
          expect(row.eventId, e.eventId);
          expect(row.saleId, e.aggregateId);
        },
      );
    }
  }
  test(
    'contrato de transferencia rechaza método, importe, cambio, referencia y admite legado',
    () async {
      await seed();
      await add();
      for (final c in [
        await command(method: 'card'),
        await command(method: 'transfer', received: 9999),
        await command(method: 'transfer', received: 10001),
        await command(method: 'transfer', reference: 'x' * 501),
      ]) {
        await expectLater(service().confirmar(c), throwsFormatException);
      }
      expect(await db.select(db.salePayments).get(), isEmpty);
      await service().confirmar(await command());
      final legacy = (await getStore().watchConfirmed().first).single.payload;
      expect(VentaConfirmadaPayload.fromJson(legacy).paymentReference, isNull);
      for (final patch in <Map<String, Object?>>[
        {
          'payment_method': 'transfer',
          'received_minor': 10001,
          'change_minor': 1,
        },
        {
          'payment_method': 'transfer',
          'received_minor': 10000,
          'change_minor': -1,
        },
        {'payment_method': 'transfer', 'received_minor': 0, 'change_minor': 0},
        {'payment_reference': 42},
        {'payment_reference': 'x' * 501},
        {'payment_method': 'card'},
        {'total_minor': 1},
      ]) {
        expect(
          () => VentaConfirmadaPayload.fromJson({...legacy, ...patch}),
          throwsA(anything),
        );
      }
      final valid = VentaConfirmadaPayload.fromJson({
        ...legacy,
        'payment_method': 'transfer',
        'received_minor': 10000,
        'change_minor': 0,
        'payment_reference': '  OK  ',
      });
      expect(
        VentaConfirmadaPayload.fromJson(valid.toJson()).paymentReference,
        'OK',
      );
      await expectLater(
        db.customStatement(
          "UPDATE sale_payments SET method = 'transfer', received_minor = 10001, change_minor = 1",
        ),
        throwsA(anything),
      );
    },
  );
  test(
    'lectura común: aplicado sin cambio, abonos una vez, anticipos y fechas propias',
    () async {
      await seed();
      await createCustomer();
      final cliente = (await db.select(db.clientes).get()).single;
      final past = DateTime(2026, 9, 20).millisecondsSinceEpoch;
      final abono = const Uuid().v4();
      await creditService().registrarAbono(
        RegistrarAbonoCommand(
          id: abono,
          clienteId: cliente.id,
          amountMinor: 5000,
          method: 'transfer',
          reference: 'ANTICIPO',
        ),
      );
      await db.customStatement(
        'UPDATE customer_payments SET occurred_at_ms = ?',
        [past],
      );
      final repo = CollectionRepositoryImpl(db);
      expect((await repo.watchCollections().first).single.amountMinor, 5000);
      await creditSale(cliente.id, 2000);
      await creditSale(cliente.id, 2000);
      expect(await db.select(db.creditAllocations).get(), hasLength(2));
      await add();
      await service().confirmar(await command(received: 20000));
      await add();
      await service().confirmar(
        await command(method: 'transfer', reference: 'DIRECTO'),
      );
      await creditService().registrarAbono(
        RegistrarAbonoCommand(
          id: const Uuid().v4(),
          clienteId: cliente.id,
          amountMinor: 1000,
          method: 'cash',
        ),
      );
      final e = (await getStore().watchConfirmed().first).singleWhere(
        (e) =>
            VentaConfirmadaPayload.fromJson(e.payload).paymentMethod ==
            'transfer',
      );
      await persistence().updateEventSyncStatus(
        e.eventId,
        'rejected',
        rejectionReason: 'Incidencia',
      );
      final rows = await repo.watchCollections().first;
      expect(rows, hasLength(4));
      expect(
        rows.fold(BigInt.zero, (n, r) => n + BigInt.from(r.amountMinor)),
        BigInt.from(10000),
      );
      expect(
        rows
            .where((r) => r.method == 'cash')
            .fold(0, (int n, r) => n + r.amountMinor),
        3000,
      );
      expect(
        rows
            .where((r) => r.method == 'transfer')
            .fold(0, (int n, r) => n + r.amountMinor),
        7000,
      );
      final advance = rows.singleWhere((r) => r.id == abono);
      expect(advance.date.millisecondsSinceEpoch, past);
      expect(advance.clienteNombre, 'Ana');
      expect(rows.where((r) => r.deliveryStatus == 'rejected'), hasLength(1));
    },
  );
}
