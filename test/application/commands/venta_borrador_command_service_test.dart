import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/sale_item_snapshot.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

void main() {
  late AppDatabase db;
  late VentaBorradorEventHandler handler;
  late AppConfigController config;
  VentaBorradorCommandService service({
    String user = 'user',
    String device = 'device',
  }) => VentaBorradorCommandService(
    store: db.saleDao,
    products: DriftProductoProjectionStore(productoDao: db.productoDao),
    units: UnidadInventarioRepositoryImpl(unitDao: db.unitDao),
    context: LocalCommandContext(userId: user, deviceId: device),
    events: DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      eventProcessor: EventProcessor(
        handlers: {ProductoAgregadoBorradorPayload.eventType: handler.apply},
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

  Future<void> measured({int price = 20000, int reference = 1000}) async {
    await db
        .update(db.products)
        .write(
          ProductsCompanion(
            saleMode: const Value('measured'),
            saleUnitId: Value(InventoryUnitIds.kilogram),
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
}
