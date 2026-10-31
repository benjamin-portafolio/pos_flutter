import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/eliminar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_actualizado_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_eliminado_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_limpiada_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_eliminado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/sale_item_snapshot.dart';
import 'package:pos_flutter/application/sync/payloads/venta_borrador_limpiada_payload.dart';
import 'package:pos_flutter/application/sync/projections/sale_item_projection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/repositories/sale_draft_repository.dart';

void main() {
  late AppDatabase db;
  late VentaBorradorEventHandler handler;
  late AppConfigController config;
  VentaBorradorCommandService service({
    String user = 'user',
    String device = 'device',
    SaleDraftRepository? drafts,
  }) => VentaBorradorCommandService(
    store: db.saleDao,
    products: DriftProductoProjectionStore(productoDao: db.productoDao),
    units: UnidadInventarioRepositoryImpl(unitDao: db.unitDao),
    context: LocalCommandContext(userId: user, deviceId: device),
    drafts: drafts,
    events: DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      eventProcessor: EventProcessor(
        handlers: {
          ProductoAgregadoBorradorPayload.eventType: handler.apply,
          ProductoActualizadoBorradorPayload.eventType:
              VentaBorradorActualizadoEventHandler(db.saleDao).apply,
          ProductoEliminadoBorradorPayload.eventType:
              VentaBorradorEliminadoEventHandler(db.saleDao).apply,
          VentaBorradorLimpiadaPayload.eventType:
              VentaBorradorLimpiadaEventHandler(db.saleDao).apply,
        },
      ),
      appConfigController: config,
    ),
  );
  Future<void> add([String variant = 'coffee']) =>
      service().agregar(AgregarProductoBorradorCommand(variantId: variant));
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    config = AppConfigController(AppConfig.initial);
    handler = VentaBorradorEventHandler(db.saleDao);
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'product', name: 'Café'));
    for (final id in ['coffee', 'bread']) {
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: id,
              createdEventId: const Value(
                '00000000-0000-4000-8000-000000000006',
              ),
              productId: 'product',
              name: Value(id),
              nameKey: Value(id),
              salePriceMinor: id == 'coffee' ? 3500 : 2500,
              standardCostMinor: const Value(1000),
              sortOrder: id == 'coffee' ? 0 : 1,
            ),
          );
    }
  });
  tearDown(() async {
    await db.close();
    config.dispose();
  });

  for (final mode in AppMode.values) {
    test(
      'crea y acumula localmente en ${mode.name}, incluso al reconstruir el servicio',
      () async {
        config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
        expect(await db.select(db.sales).get(), isEmpty);
        await add();
        final original = (await db.select(db.sales).get()).single;
        await add();
        await add('bread');
        final sale = (await db.select(db.sales).get()).single;
        final items = await db.saleDao.items(sale.id);
        expect(sale.id, original.id);
        expect(sale.createdAtLocal, original.createdAtLocal);
        expect(sale.status, 'borrador');
        expect(sale.totalMinor, 9500);
        expect(sale.version, 3);
        expect(items, hasLength(2));
        expect(items.first.snapshot.quantity, 2);
        expect(items.first.version, 2);
        expect(items.map((i) => i.sortOrder), [0, 1]);
        expect(items.first.snapshot.standardCostMinor, 1000);
        expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
        final events = await db.select(db.events).get();
        expect(events, hasLength(3));
        expect(events.every((e) => e.deliveryStatus == 'not_required'), isTrue);
        final refs = await db.select(db.eventRefs).get();
        expect(refs.length, mode == AppMode.standalone ? 0 : 12);
        expect(await db.select(db.inventoryMovements).get(), isEmpty);
      },
    );
  }

  for (final mode in AppMode.values) {
    test(
      'pestañas aíslan captura, edición y limpieza en ${mode.name}',
      () async {
        config.dispose();
        config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
        final repository = SaleDraftRepositoryImpl(
          saleDao: db.saleDao,
          userId: 'user',
          deviceId: 'device',
        );
        final commands = service(drafts: repository);
        repository.selectDraft('sale-1');
        final first = commands.agregar(
          const AgregarProductoBorradorCommand(variantId: 'coffee'),
        );
        repository.selectDraft('sale-2');
        final second = commands.agregar(
          const AgregarProductoBorradorCommand(variantId: 'bread'),
        );
        await Future.wait([first, second]);
        final open = await repository.watchDrafts().first;
        expect(open.map((sale) => sale.id).toSet(), {'sale-1', 'sale-2'});
        expect(
          (await db.saleDao.items('sale-1')).single.snapshot.variantId,
          'coffee',
        );
        expect(
          (await db.saleDao.items('sale-2')).single.snapshot.variantId,
          'bread',
        );
        expect((await repository.watchCurrentDraft().first)!.id, 'sale-2');
        final line = (await db.saleDao.items('sale-2')).single;
        await commands.actualizarProducto(
          ActualizarProductoBorradorCommand(saleItemId: line.id, quantity: 3),
        );
        expect((await db.saleDao.findById('sale-2'))!.totalMinor, 7500);
        expect((await db.saleDao.findById('sale-1'))!.totalMinor, 3500);
        final otherLine = (await db.saleDao.items('sale-1')).single;
        await expectLater(
          commands.eliminarProducto(
            EliminarProductoBorradorCommand(saleItemId: otherLine.id),
          ),
          throwsStateError,
        );
        await commands.eliminarProducto(
          EliminarProductoBorradorCommand(saleItemId: line.id),
        );
        expect((await db.saleDao.findById('sale-2'))!.totalMinor, 0);
        await commands.limpiar(
          const LimpiarVentaBorradorCommand(saleId: 'sale-2'),
        );
        expect((await repository.watchDrafts().first).single.id, 'sale-1');
        await expectLater(
          commands.agregar(
            const AgregarProductoBorradorCommand(variantId: 'bread'),
          ),
          throwsStateError,
        );
        expect(await db.saleDao.findById('sale-2'), isNull);
        expect(
          (await db.select(db.events).get()).every(
            (event) => event.deliveryStatus == 'not_required',
          ),
          isTrue,
        );
        expect(await db.select(db.inventoryMovements).get(), isEmpty);
        if (mode == AppMode.standalone) {
          expect(await db.select(db.eventRefs).get(), isEmpty);
        }
      },
    );
  }

  test(
    'seleccionar una venta ajena o confirmada no permite editarla',
    () async {
      await add();
      final original = (await db.select(db.sales).get()).single;
      final repository = SaleDraftRepositoryImpl(
        saleDao: db.saleDao,
        userId: 'second',
        deviceId: 'device',
      )..selectDraft(original.id);
      await expectLater(
        service(
          user: 'second',
          drafts: repository,
        ).agregar(const AgregarProductoBorradorCommand(variantId: 'bread')),
        throwsStateError,
      );
      await (db.update(db.sales)..where((sale) => sale.id.equals(original.id)))
          .write(const SalesCompanion(status: Value('confirmada')));
      await expectLater(
        service(
          drafts: repository,
        ).agregar(const AgregarProductoBorradorCommand(variantId: 'bread')),
        throwsStateError,
      );
      expect((await db.saleDao.items(original.id)).single.snapshot.quantity, 1);
      expect(await db.select(db.events).get(), hasLength(1));
    },
  );

  SyncEvent eventFrom(EventRecord record) => SyncEvent.fromJson({
    'event_id': record.eventId,
    'aggregate_type': record.aggregateType,
    'aggregate_id': record.aggregateId,
    'event_type': record.eventType,
    'device_id': record.deviceId,
    'user_id': record.userId,
    'created_at_local': record.createdAtLocal.toIso8601String(),
    'base_version': record.baseVersion,
    'delivery_status': record.deliveryStatus,
    'payload': jsonDecode(record.payload),
  });

  for (final mode in AppMode.values) {
    test(
      'limpiar borra sólo la venta indicada y sigue siendo local en ${mode.name}',
      () async {
        config.dispose();
        config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
        await add();
        await add('bread');
        final sale = (await db.select(db.sales).get()).single;
        final addedEvents = await db.select(db.events).get();
        await service(
          user: 'second',
        ).agregar(const AgregarProductoBorradorCommand(variantId: 'coffee'));
        final otherSale = await db.saleDao.findDraft('second', 'device');
        // También se eliminan líneas inactivas de esta venta.
        await (db.update(db.saleItems)..where(
              (t) => t.saleId.equals(sale.id) & t.variantId.equals('bread'),
            ))
            .write(const SaleItemsCompanion(active: Value(false)));
        final command = LimpiarVentaBorradorCommand(saleId: '  ${sale.id}  ');
        await service().limpiar(command);
        expect(await db.saleDao.findById(sale.id), isNull);
        expect(await db.saleDao.items(sale.id), isEmpty);
        expect((await db.select(db.sales).get()).single.id, otherSale!.id);
        expect(await db.saleDao.items(otherSale.id), hasLength(1));
        expect(await db.select(db.productVariants).get(), hasLength(2));
        expect(await db.select(db.inventoryMovements).get(), isEmpty);
        final events = await db.select(db.events).get();
        expect(events, hasLength(4));
        expect(
          events.every((event) => event.deliveryStatus == 'not_required'),
          isTrue,
        );
        final cleanup = events.last;
        expect(cleanup.eventType, VentaBorradorLimpiadaPayload.eventType);
        final refs = await (db.select(
          db.eventRefs,
        )..where((t) => t.eventId.equals(cleanup.eventId))).get();
        expect(refs.length, mode == AppMode.standalone ? 0 : 3);
        await service().limpiar(command);
        await VentaBorradorLimpiadaEventHandler(
          db.saleDao,
        ).apply(eventFrom(cleanup));
        for (final event in addedEvents) {
          await handler.apply(eventFrom(event));
        }
        expect(await db.saleDao.findById(sale.id), isNull);
        expect(await db.saleDao.items(sale.id), isEmpty);
        expect(await db.select(db.events).get(), hasLength(4));
        await add();
        final next = await db.saleDao.findDraft('user', 'device');
        expect(next!.id, isNot(sale.id));
        expect((await db.saleDao.items(next.id)).single.snapshot.quantity, 1);
      },
    );
  }

  test('limpiar valida venta y propietario antes de escribir', () async {
    await add();
    final sale = (await db.select(db.sales).get()).single;
    await expectLater(
      service().limpiar(const LimpiarVentaBorradorCommand(saleId: '  ')),
      throwsFormatException,
    );
    for (final foreign in [
      service(user: 'second'),
      service(device: 'second'),
    ]) {
      await expectLater(
        foreign.limpiar(LimpiarVentaBorradorCommand(saleId: sale.id)),
        throwsStateError,
      );
    }
    expect(await db.select(db.events).get(), hasLength(1));
    expect(await db.saleDao.items(sale.id), hasLength(1));
  });

  test(
    'fallo al borrar la venta revierte líneas, evento y referencias',
    () async {
      config.dispose();
      config = AppConfigController(
        AppConfig.initial.copyWith(mode: AppMode.serverSync),
      );
      await add();
      final sale = (await db.select(db.sales).get()).single;
      await db.customStatement(
        "CREATE TRIGGER reject_clear BEFORE DELETE ON sales BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        service().limpiar(LimpiarVentaBorradorCommand(saleId: sale.id)),
        throwsA(anything),
      );
      expect(await db.saleDao.findById(sale.id), isNotNull);
      expect(await db.saleDao.items(sale.id), hasLength(1));
      expect(await db.select(db.events).get(), hasLength(1));
      expect(await db.select(db.eventRefs).get(), hasLength(4));
      expect(await db.saleDao.wasCleared(sale.id), isFalse);
    },
  );

  test(
    'lectura reactiva observa borrador propio, precios capturados, totales y limpieza',
    () async {
      final repository = SaleDraftRepositoryImpl(
        saleDao: db.saleDao,
        userId: 'user',
        deviceId: 'device',
      );
      final stream = repository.watchCurrentDraft().asBroadcastStream();
      expect(await stream.first, isNull);
      var next = stream.firstWhere((sale) => sale != null);
      await add();
      final first = (await next)!;
      expect(first.items.single.productName, 'Café');
      next = stream.firstWhere((sale) => sale?.totalMinor == 7500);
      await (db.update(db.productVariants)..where((t) => t.id.equals('coffee')))
          .write(const ProductVariantsCompanion(salePriceMinor: Value(4000)));
      await add();
      final changed = (await next)!;
      expect(changed.articleCount, 1);
      expect(changed.items.map((item) => item.unitPriceMinor), [3500, 4000]);
      expect(changed.items.map((item) => item.totalMinor), [3500, 4000]);
      await service(
        user: 'second',
      ).agregar(const AgregarProductoBorradorCommand(variantId: 'bread'));
      expect((await repository.watchCurrentDraft().first)!.id, first.id);
      final empty = stream.firstWhere((sale) => sale == null);
      await service().limpiar(LimpiarVentaBorradorCommand(saleId: first.id));
      expect(await empty, isNull);
      expect(await db.saleDao.findDraft('second', 'device'), isNotNull);
    },
  );

  test(
    'reaplicar eventos antiguos o recientes no duplica cantidades',
    () async {
      await add();
      await add();
      final records = await db.select(db.events).get();
      for (final record in [records.first, records.last, records.last]) {
        await handler.apply(
          SyncEvent.fromJson({
            'event_id': record.eventId,
            'aggregate_type': record.aggregateType,
            'aggregate_id': record.aggregateId,
            'event_type': record.eventType,
            'device_id': record.deviceId,
            'user_id': record.userId,
            'created_at_local': record.createdAtLocal.toIso8601String(),
            'base_version': record.baseVersion,
            'delivery_status': record.deliveryStatus,
            'payload': jsonDecode(record.payload),
          }),
        );
      }
      expect((await db.select(db.saleItems).get()).single.quantity, 2);
      expect((await db.select(db.sales).get()).single.totalMinor, 7000);
    },
  );

  test(
    'un precio nuevo crea otra línea y conserva el precio original',
    () async {
      await add();
      await (db.update(db.productVariants)..where((t) => t.id.equals('coffee')))
          .write(const ProductVariantsCompanion(salePriceMinor: Value(4000)));
      await add();
      final sale = (await db.select(db.sales).get()).single;
      final lines = await db.saleDao.items(sale.id);
      expect(lines.map((l) => l.snapshot.unitPriceMinor), [3500, 4000]);
      expect(sale.totalMinor, 7500);
    },
  );

  test('usuarios y dispositivos conservan borradores distintos', () async {
    await add();
    await service(
      user: 'second',
    ).agregar(const AgregarProductoBorradorCommand(variantId: 'coffee'));
    await service(
      device: 'second',
    ).agregar(const AgregarProductoBorradorCommand(variantId: 'coffee'));
    expect(await db.select(db.sales).get(), hasLength(3));
  });

  test(
    'toques concurrentes no pierden cantidades ni crean dos borradores',
    () async {
      await Future.wait([add(), add(), add('bread')]);
      expect(await db.select(db.sales).get(), hasLength(1));
      expect((await db.select(db.sales).get()).single.totalMinor, 9500);
    },
  );

  test(
    'desbordamiento del total revierte el agregado y conserva la captura previa',
    () async {
      await (db.update(
        db.productVariants,
      )..where((t) => t.id.equals('coffee'))).write(
        const ProductVariantsCompanion(
          salePriceMinor: Value(SaleItemSnapshot.maxInteger),
        ),
      );
      await add();
      await expectLater(add('bread'), throwsFormatException);
      expect(
        (await db.select(db.sales).get()).single.totalMinor,
        SaleItemSnapshot.maxInteger,
      );
      expect(await db.select(db.saleItems).get(), hasLength(1));
      expect(await db.select(db.events).get(), hasLength(1));
    },
  );

  test('artículo desactivado no genera venta, línea ni evento', () async {
    await (db.update(db.products)..where((t) => t.id.equals('product'))).write(
      const ProductsCompanion(active: Value(false)),
    );
    await expectLater(add(), throwsStateError);
    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.saleItems).get(), isEmpty);
    expect(await db.select(db.events).get(), isEmpty);
  });

  test('fallo al guardar línea revierte venta, evento y referencias', () async {
    config = AppConfigController(
      AppConfig.initial.copyWith(mode: AppMode.serverSync),
    );
    await db.customStatement(
      "CREATE TRIGGER reject_line BEFORE INSERT ON sale_items BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(add(), throwsA(anything));
    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.saleItems).get(), isEmpty);
    expect(await db.select(db.events).get(), isEmpty);
    expect(await db.select(db.eventRefs).get(), isEmpty);
  });

  Future<void> measured({
    int price = 20000,
    int reference = 1000,
    String unitId = InventoryUnitIds.kilogram,
  }) async {
    await db
        .update(db.products)
        .write(
          ProductsCompanion(
            saleMode: const Value('measured'),
            saleUnitId: Value(unitId),
            priceReferenceQuantityAtomic: Value(reference),
          ),
        );
    await (db.update(db.productVariants)..where((t) => t.id.equals('coffee')))
        .write(ProductVariantsCompanion(salePriceMinor: Value(price)));
  }

  Future<void> weigh(String value) => service().agregar(
    AgregarProductoBorradorCommand(
      variantId: 'coffee',
      measuredQuantity: value,
      expectedUnitId: InventoryUnitIds.kilogram,
    ),
  );

  AgregarProductoBorradorCommand byAmount({
    int amount = 2000,
    int price = 6000,
    int reference = 1000,
    String unitId = InventoryUnitIds.kilogram,
  }) => AgregarProductoBorradorCommand(
    variantId: 'coffee',
    targetAmountMinor: amount,
    expectedUnitId: unitId,
    expectedUnitPriceMinor: price,
    expectedPriceReferenceQuantityAtomic: reference,
  );

  Future<void> rejectsWithoutWrites(
    Future<void> Function() action,
    Matcher error,
  ) async {
    Future<List<Object>> state() async => [
      await db.select(db.sales).get(),
      await db.select(db.saleItems).get(),
      await db.select(db.events).get(),
      await db.select(db.eventRefs).get(),
      await db.select(db.inventoryMovements).get(),
    ];
    final before = await state();
    await expectLater(action(), error);
    expect(await state(), before);
  }

  for (final mode in AppMode.values) {
    group('importe objetivo en ${mode.name}', () {
      setUp(() {
        config.dispose();
        config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
      });

      for (final (unitId, code, price, reference, amount, atomic, total) in [
        (InventoryUnitIds.kilogram, 'kg', 6000, 1000, 2000, 334, 2004),
        (InventoryUnitIds.gram, 'g', 6000, 1000, 2000, 334, 2004),
        (InventoryUnitIds.kilogram, 'kg', 8000, 1000, 2000, 250, 2000),
        (InventoryUnitIds.gram, 'g', 1200, 100, 2000, 167, 2004),
        (InventoryUnitIds.liter, 'l', 4000, 1000, 1500, 375, 1500),
        (InventoryUnitIds.milliliter, 'ml', 4000, 1000, 1500, 375, 1500),
        (InventoryUnitIds.kilogram, 'kg', 6000, 1000, 1, 1, 6),
        (InventoryUnitIds.gram, 'g', 3, 2, 1, 1, 2),
      ]) {
        test('$amount a $price por $reference átomos, unidad $code', () async {
          await measured(price: price, reference: reference, unitId: unitId);
          await service().agregar(
            byAmount(
              amount: amount,
              price: price,
              reference: reference,
              unitId: unitId,
            ),
          );
          final sale = (await db.select(db.sales).get()).single;
          final line = (await db.saleDao.items(sale.id)).single;
          expect(line.snapshot.measuredQuantityAtomic, atomic);
          expect(line.snapshot.quantity, isNull);
          expect(line.snapshot.unitPriceMinor, price);
          expect(line.snapshot.priceReferenceQuantityAtomic, reference);
          expect(line.snapshot.unitCode, code);
          expect(
            line.snapshot.unitAtomicFactor,
            ['kg', 'l'].contains(code) ? 1000 : 1,
          );
          expect(line.snapshot.totalMinor, total);
          expect(sale.totalMinor, total);
          final event = (await db.select(db.events).get()).single;
          expect(event.eventType, ProductoAgregadoBorradorPayload.eventType);
          expect(event.deliveryStatus, 'not_required');
          expect(event.applicationStatus, 'applied');
          final payload = jsonDecode(event.payload) as Map<String, dynamic>;
          expect(payload, {
            'sale_item_id': line.id,
            'sort_order': 0,
            ...line.snapshot.toJson(),
          });
          expect(
            ProductoAgregadoBorradorPayload.fromJson(payload).toJson(),
            payload,
          );
          final refs = await db.select(db.eventRefs).get();
          if (mode == AppMode.standalone) {
            expect(refs, isEmpty);
          } else {
            expect(
              refs.map((ref) => (ref.refType, ref.refId, ref.relationship)),
              unorderedEquals([
                ('sale', sale.id, 'affects'),
                ('sale_item', line.id, 'affects'),
                ('product', 'product', 'uses'),
                ('product_variant', 'coffee', 'uses'),
                ('unit', unitId, 'uses'),
              ]),
            );
          }
          expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
          expect(await db.select(db.inventoryMovements).get(), isEmpty);
        });
      }

      test('acumula 668 g y 4008 centavos; replay no duplica', () async {
        await measured(price: 6000);
        await service().agregar(byAmount());
        await service().agregar(byAmount());
        final sale = (await db.select(db.sales).get()).single;
        final originalLine = (await db.select(db.saleItems).get()).single;
        expect(originalLine.measuredQuantityAtomic, 668);
        expect(originalLine.totalMinor, 4008);
        final records = await db.select(db.events).get();
        expect(records, hasLength(2));
        expect(
          records.every((event) => event.deliveryStatus == 'not_required'),
          isTrue,
        );
        for (final record in [records.first, records.last, records.last]) {
          await handler.apply(eventFrom(record));
        }
        expect((await db.select(db.saleItems).get()).single, originalLine);
        expect((await db.select(db.sales).get()).single, sale);
        expect(await db.select(db.events).get(), records);
      });

      test(
        'mezcla peso e importe y redondea solo la cantidad acumulada',
        () async {
          await measured(price: 1, reference: 3);
          await weigh('0.001');
          expect((await db.select(db.saleItems).get()).single.totalMinor, 0);
          await service().agregar(byAmount(amount: 1, price: 1, reference: 3));
          var line = (await db.select(db.saleItems).get()).single;
          expect(line.measuredQuantityAtomic, 4);
          expect(line.totalMinor, 1);
          await service().agregar(byAmount(amount: 2, price: 1, reference: 3));
          line = (await db.select(db.saleItems).get()).single;
          expect(line.measuredQuantityAtomic, 10);
          expect(line.totalMinor, 3);
          expect((await db.select(db.sales).get()).single.totalMinor, 3);
        },
      );

      test('exige una fuente y condiciones esperadas completas', () async {
        await measured(price: 6000);
        for (final command in [
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            expectedUnitId: InventoryUnitIds.kilogram,
          ),
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            measuredQuantity: '0.3',
            targetAmountMinor: 2000,
            expectedUnitId: InventoryUnitIds.kilogram,
            expectedUnitPriceMinor: 6000,
            expectedPriceReferenceQuantityAtomic: 1000,
          ),
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            targetAmountMinor: 2000,
            expectedUnitPriceMinor: 6000,
            expectedPriceReferenceQuantityAtomic: 1000,
          ),
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            targetAmountMinor: 2000,
            expectedUnitId: InventoryUnitIds.kilogram,
            expectedPriceReferenceQuantityAtomic: 1000,
          ),
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            targetAmountMinor: 2000,
            expectedUnitId: InventoryUnitIds.kilogram,
            expectedUnitPriceMinor: 6000,
          ),
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            measuredQuantity: '0.3',
            expectedUnitId: InventoryUnitIds.kilogram,
            expectedUnitPriceMinor: 6000,
          ),
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            measuredQuantity: '0.3',
            expectedUnitId: InventoryUnitIds.kilogram,
            expectedPriceReferenceQuantityAtomic: 1000,
          ),
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            measuredQuantity: '0.3',
            expectedUnitPriceMinor: 6000,
            expectedPriceReferenceQuantityAtomic: 1000,
          ),
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            measuredQuantity: ' ',
            expectedUnitId: InventoryUnitIds.kilogram,
          ),
        ]) {
          await rejectsWithoutWrites(
            () => service().agregar(command),
            throwsFormatException,
          );
        }
        expect(await db.select(db.events).get(), isEmpty);
        expect(await db.select(db.sales).get(), isEmpty);
      });

      test('rechaza importes inválidos y excedentes sin escrituras', () async {
        await measured(price: 6000);
        for (final amount in [0, -1, SaleItemSnapshot.maxInteger + 1]) {
          await rejectsWithoutWrites(
            () => service().agregar(byAmount(amount: amount)),
            throwsFormatException,
          );
        }
        await measured(price: 1, reference: SaleItemSnapshot.maxInteger);
        await rejectsWithoutWrites(
          () => service().agregar(
            byAmount(
              amount: SaleItemSnapshot.maxInteger,
              price: 1,
              reference: SaleItemSnapshot.maxInteger,
            ),
          ),
          throwsFormatException,
        );
        await measured(price: 2, reference: 1);
        await rejectsWithoutWrites(
          () => service().agregar(
            byAmount(
              amount: SaleItemSnapshot.maxInteger,
              price: 2,
              reference: 1,
            ),
          ),
          throwsFormatException,
        );
      });

      for (final captureAmount in [true, false]) {
        for (final change in ['price', 'reference', 'unit']) {
          test(
            'rechaza $change obsoleto por ${captureAmount ? 'importe' : 'peso'}',
            () async {
              await measured(price: 6000);
              await service().agregar(byAmount());
              final command = captureAmount
                  ? byAmount()
                  : const AgregarProductoBorradorCommand(
                      variantId: 'coffee',
                      measuredQuantity: '0.333',
                      expectedUnitId: InventoryUnitIds.kilogram,
                      expectedUnitPriceMinor: 6000,
                      expectedPriceReferenceQuantityAtomic: 1000,
                    );
              if (change == 'price') {
                await (db.update(
                  db.productVariants,
                )..where((t) => t.id.equals('coffee'))).write(
                  const ProductVariantsCompanion(salePriceMinor: Value(8000)),
                );
              } else if (change == 'reference') {
                await db
                    .update(db.products)
                    .write(
                      const ProductsCompanion(
                        priceReferenceQuantityAtomic: Value(100),
                      ),
                    );
              } else {
                await db
                    .update(db.products)
                    .write(
                      const ProductsCompanion(
                        saleUnitId: Value(InventoryUnitIds.gram),
                      ),
                    );
              }
              await rejectsWithoutWrites(
                () => service().agregar(command),
                throwsStateError,
              );
            },
          );
        }
      }

      test(
        'captura manual acepta condiciones completas y normaliza texto',
        () async {
          await measured(price: 6000);
          await service().agregar(
            const AgregarProductoBorradorCommand(
              variantId: ' coffee ',
              measuredQuantity: ' 0,333 ',
              expectedUnitId: ' ${InventoryUnitIds.kilogram} ',
              expectedUnitPriceMinor: 6000,
              expectedPriceReferenceQuantityAtomic: 1000,
            ),
          );
          final line = (await db.select(db.saleItems).get()).single;
          expect(line.measuredQuantityAtomic, 333);
          expect(line.totalMinor, 1998);
        },
      );

      test(
        'piezas rechazan importe o condiciones medidas; legado funciona',
        () async {
          for (final command in [
            byAmount(),
            const AgregarProductoBorradorCommand(
              variantId: 'coffee',
              targetAmountMinor: 2000,
            ),
            const AgregarProductoBorradorCommand(
              variantId: 'coffee',
              expectedUnitPriceMinor: 3500,
            ),
            const AgregarProductoBorradorCommand(
              variantId: 'coffee',
              expectedPriceReferenceQuantityAtomic: 1,
            ),
          ]) {
            await rejectsWithoutWrites(
              () => service().agregar(command),
              throwsStateError,
            );
          }
          await add();
          expect((await db.select(db.saleItems).get()).single.quantity, 1);
        },
      );

      test('valida contexto y refs antes de escribir en ambos modos', () async {
        await measured(price: 6000);
        await rejectsWithoutWrites(
          () => service(user: ' ').agregar(byAmount()),
          throwsStateError,
        );
        await rejectsWithoutWrites(
          () => service(device: '').agregar(byAmount()),
          throwsStateError,
        );
      });

      test(
        'BigInt admite límite seguro y rechaza acumulación fuera de rango',
        () async {
          const max = SaleItemSnapshot.maxInteger;
          await measured(price: max, reference: max);
          await service().agregar(
            byAmount(amount: max, price: max, reference: max),
          );
          expect(
            (await db.select(db.saleItems).get()).single.measuredQuantityAtomic,
            max,
          );
          expect((await db.select(db.sales).get()).single.totalMinor, max);
          await rejectsWithoutWrites(
            () => service().agregar(
              byAmount(amount: 1, price: max, reference: max),
            ),
            throwsFormatException,
          );
        },
      );
    });
  }

  test(
    'cantidad medida usa snapshot y redondea una vez sobre la cantidad acumulada',
    () async {
      await measured(price: 1, reference: 3);
      await weigh('0.001');
      await weigh('0.001');
      final line = (await db.select(db.saleItems).get()).single;
      expect(line.quantity, isNull);
      expect(line.measuredQuantityAtomic, 2);
      expect(line.totalMinor, 1);
      expect(line.saleUnitCodeSnapshot, 'kg');
      expect(line.saleUnitAtomicFactorSnapshot, 1000);
      expect(line.priceReferenceQuantityAtomicSnapshot, 3);
      expect((await db.select(db.sales).get()).single.totalMinor, 1);
    },
  );

  test('250 gramos a 200 pesos por kilo cuestan 50 pesos', () async {
    await measured();
    await weigh('0,25');
    expect((await db.select(db.sales).get()).single.totalMinor, 5000);
  });

  test(
    'rechaza cantidades inválidas, cambio de unidad y desbordamiento',
    () async {
      await measured();
      for (final value in ['0', '-1', '0.0001', 'texto', '9007199254740992']) {
        await expectLater(weigh(value), throwsFormatException);
      }
      await expectLater(
        service().agregar(
          const AgregarProductoBorradorCommand(
            variantId: 'coffee',
            measuredQuantity: '1',
            expectedUnitId: 'changed',
          ),
        ),
        throwsStateError,
      );
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.events).get(), isEmpty);
    },
  );

  test(
    'contrato tipado conserva snapshots, null y rechaza cantidades fraccionarias',
    () async {
      await add();
      final item = (await db.saleDao.items(
        (await db.select(db.sales).get()).single.id,
      )).single;
      final payload = ProductoAgregadoBorradorPayload(
        saleItemId: item.id,
        sortOrder: item.sortOrder,
        item: item.snapshot,
      );
      expect(
        ProductoAgregadoBorradorPayload.fromJson(payload.toJson()).toJson(),
        payload.toJson(),
      );
      expect(
        () => SaleItemSnapshot.fromJson({
          ...item.snapshot.toJson(),
          'quantity': 1.5,
        }),
        throwsFormatException,
      );
      expect(
        () => SaleItemSnapshot.fromJson({
          ...item.snapshot.toJson(),
          'measured_quantity_atomic': 100,
        }),
        throwsFormatException,
      );
    },
  );

  Future<SaleItemProjection> onlyLine() async => (await db.saleDao.items(
    (await db.select(db.sales).get()).single.id,
  )).single;

  test(
    'actualizar cantidad por piezas recalcula línea, totales y conserva precio',
    () async {
      await add(); // 1 × $35
      await add('bread'); // 1 × $25
      final sale = (await db.select(db.sales).get()).single;
      final coffee = (await db.saleDao.items(
        sale.id,
      )).firstWhere((line) => line.sortOrder == 0);
      await service().actualizarProducto(
        ActualizarProductoBorradorCommand(saleItemId: coffee.id, quantity: 3),
      );
      final after = (await db.select(db.sales).get()).single;
      final lines = await db.saleDao.items(sale.id);
      expect(after.version, 3);
      expect(after.totalMinor, 13000); // 3 × 3500 + 2500
      final updated = lines.firstWhere((line) => line.id == coffee.id);
      expect(updated.snapshot.quantity, 3);
      expect(updated.snapshot.unitPriceMinor, 3500);
      expect(updated.snapshot.standardCostMinor, 1000);
      expect(updated.sortOrder, 0);
      expect(updated.version, 2);
      expect(
        lines.firstWhere((line) => line.id != coffee.id).snapshot.quantity,
        1,
      );
      final events = await db.select(db.events).get();
      expect(events, hasLength(3));
      final update = events.last;
      expect(update.eventType, ProductoActualizadoBorradorPayload.eventType);
      expect(update.deliveryStatus, 'not_required');
      expect(await db.select(db.inventoryMovements).get(), isEmpty);
    },
  );

  test(
    'actualizar medida usa la unidad capturada y ajusta el importe',
    () async {
      await measured();
      await weigh('0.5'); // 500 g → $10000
      final item = await onlyLine();
      await service().actualizarProducto(
        ActualizarProductoBorradorCommand(
          saleItemId: item.id,
          measuredQuantity: '1,750',
        ),
      );
      final line = await onlyLine();
      expect(line.snapshot.measuredQuantityAtomic, 1750);
      expect(line.snapshot.unitPriceMinor, 20000);
      expect(line.snapshot.priceReferenceQuantityAtomic, 1000);
      expect(line.snapshot.unitCode, 'kg');
      expect((await db.select(db.sales).get()).single.totalMinor, 35000);
    },
  );

  test('rechaza cantidades inválidas sin cambiar el borrador', () async {
    await add();
    await add('bread');
    final coffee = (await db.saleDao.items(
      (await db.select(db.sales).get()).single.id,
    )).first;
    for (final quantity in <int?>[null, 0, -3]) {
      await expectLater(
        service().actualizarProducto(
          ActualizarProductoBorradorCommand(
            saleItemId: coffee.id,
            quantity: quantity,
          ),
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      service().actualizarProducto(
        const ActualizarProductoBorradorCommand(saleItemId: '', quantity: 2),
      ),
      throwsFormatException,
    );
    await expectLater(
      service().actualizarProducto(
        ActualizarProductoBorradorCommand(
          saleItemId: coffee.id,
          measuredQuantity: '2',
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      service().actualizarProducto(
        const ActualizarProductoBorradorCommand(
          saleItemId: 'missing',
          quantity: 2,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      service(user: 'second').actualizarProducto(
        ActualizarProductoBorradorCommand(saleItemId: coffee.id, quantity: 2),
      ),
      throwsStateError,
    );
    expect((await db.select(db.events).get()), hasLength(2));
    expect((await db.select(db.sales).get()).single.totalMinor, 6000);
  });

  test('rechaza medidas inválidas, vacías o fuera de precisión', () async {
    await measured();
    await weigh('0.5');
    final item = await onlyLine();
    for (final value in ['', '0', '0.0001', '9007199254740992', '1kg']) {
      await expectLater(
        service().actualizarProducto(
          ActualizarProductoBorradorCommand(
            saleItemId: item.id,
            measuredQuantity: value,
          ),
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      service().actualizarProducto(
        ActualizarProductoBorradorCommand(saleItemId: item.id, quantity: 2),
      ),
      throwsStateError,
    );
    expect(await db.select(db.events).get(), hasLength(1));
    expect((await db.select(db.sales).get()).single.totalMinor, 10000);
  });

  test('actualizar sin cambios no registra un evento nuevo', () async {
    await add();
    final item = await onlyLine();
    await service().actualizarProducto(
      ActualizarProductoBorradorCommand(saleItemId: item.id, quantity: 1),
    );
    expect((await db.select(db.sales).get()).single.version, 1);
    expect(await db.select(db.events).get(), hasLength(1));
  });

  test('eliminar sólo la línea indicada recalcula el total', () async {
    await add();
    await add('bread');
    final sale = (await db.select(db.sales).get()).single;
    final lines = await db.saleDao.items(sale.id);
    final coffee = lines.firstWhere((line) => line.sortOrder == 0);
    await service().eliminarProducto(
      EliminarProductoBorradorCommand(saleItemId: coffee.id),
    );
    final after = (await db.select(db.sales).get()).single;
    expect(after.version, 3);
    expect(after.totalMinor, 2500);
    final remaining = await db.saleDao.items(sale.id);
    expect(remaining, hasLength(1));
    expect(remaining.single.id, isNot(coffee.id));
    final events = await db.select(db.events).get();
    expect(events.last.eventType, ProductoEliminadoBorradorPayload.eventType);
    expect(await db.select(db.productVariants).get(), hasLength(2));
    expect(await db.select(db.inventoryMovements).get(), isEmpty);
  });

  test('eliminar la última línea deja el borrador en cero', () async {
    await add();
    final sale = (await db.select(db.sales).get()).single;
    final item = (await db.saleDao.items(sale.id)).single;
    await service().eliminarProducto(
      EliminarProductoBorradorCommand(saleItemId: item.id),
    );
    final after = (await db.select(db.sales).get()).single;
    expect(after.totalMinor, 0);
    expect(after.version, 2);
    expect(await db.saleDao.items(sale.id), isEmpty);
    expect(await db.saleDao.findById(sale.id), isNotNull);
    final repository = SaleDraftRepositoryImpl(
      saleDao: db.saleDao,
      userId: 'user',
      deviceId: 'device',
    );
    final draft = await repository.watchCurrentDraft().first;
    expect(draft!.items, isEmpty);
    expect(draft.totalMinor, 0);
  });

  test('eliminar valida propietario, línea y contexto', () async {
    await add();
    final item = await onlyLine();
    await expectLater(
      service(
        user: 'second',
      ).eliminarProducto(EliminarProductoBorradorCommand(saleItemId: item.id)),
      throwsStateError,
    );
    await expectLater(
      service().eliminarProducto(
        const EliminarProductoBorradorCommand(saleItemId: 'missing'),
      ),
      throwsStateError,
    );
    await expectLater(
      service().eliminarProducto(
        const EliminarProductoBorradorCommand(saleItemId: '  '),
      ),
      throwsFormatException,
    );
    expect((await db.select(db.sales).get()).single.totalMinor, 3500);
    expect(await db.select(db.events).get(), hasLength(1));
  });

  test('reaplicar edición o eliminación no modifica ni duplica', () async {
    await add();
    await add('bread');
    final sale = (await db.select(db.sales).get()).single;
    final lines = await db.saleDao.items(sale.id);
    final coffee = lines.firstWhere((line) => line.sortOrder == 0);
    await service().actualizarProducto(
      ActualizarProductoBorradorCommand(saleItemId: coffee.id, quantity: 3),
    );
    await service().eliminarProducto(
      EliminarProductoBorradorCommand(
        saleItemId: lines.firstWhere((line) => line.id != coffee.id).id,
      ),
    );
    expect((await db.select(db.sales).get()).single.totalMinor, 10500);
    final records = await db.select(db.events).get();
    final update = records.firstWhere(
      (event) =>
          event.eventType == ProductoActualizadoBorradorPayload.eventType,
    );
    final remove = records.firstWhere(
      (event) => event.eventType == ProductoEliminadoBorradorPayload.eventType,
    );
    final updateHandler = VentaBorradorActualizadoEventHandler(db.saleDao);
    final removeHandler = VentaBorradorEliminadoEventHandler(db.saleDao);
    for (var i = 0; i < 2; i++) {
      await updateHandler.apply(eventFrom(update));
      await removeHandler.apply(eventFrom(remove));
    }
    final after = (await db.select(db.sales).get()).single;
    expect(after.version, 4);
    expect(after.totalMinor, 10500);
    final remaining = await db.saleDao.items(sale.id);
    expect(remaining, hasLength(1));
    expect(remaining.single.snapshot.quantity, 3);
    expect(await db.select(db.events).get(), hasLength(4));
  });
}
