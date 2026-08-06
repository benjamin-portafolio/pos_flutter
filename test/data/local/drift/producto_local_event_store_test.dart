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
    test(
      '${mode.name} aplica producto y variante en una transacción',
      () async {
        final store = _store(mode, db, productoDao, eventDao);
        await store.appendAndApply(
          _event(),
          refs: const [
            LocalEventRef.affects(refType: 'product', refId: 'product_1'),
            LocalEventRef.affects(
              refType: 'product_variant',
              refId: 'variant_1',
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
        expect(variants, hasLength(1));
        expect(variants.single.salePriceMinor, 4550);
        expect(variants.single.isDefault, isTrue);
        expect(variants.single.inventoryBehavior, 'none');
        expect(
          storedEvent.deliveryStatus,
          mode == AppMode.standalone ? 'not_required' : 'pending',
        );
        expect(refs, mode == AppMode.standalone ? isEmpty : hasLength(2));
      },
    );
  }

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
      varianteId: 'variant_1',
      precioVentaMenor: 4550,
    ).toJson(),
  );
}
