import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_variant_inventory_memory_store.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';

Map<String, Object?> obj(Object? v) => Map<String, Object?>.from(v as Map);
void main() {
  final fixture = obj(
    jsonDecode(File('contracts/offer_pricing/v2.json').readAsStringSync()),
  );
  Map<String, Object?> value(String key) =>
      obj(jsonDecode(jsonEncode(fixture[key])));
  test(
    'producto legado, null conocido y oferta preservan presencia en round-trip',
    () {
      for (final key in ['product', 'product_null', 'product_legacy']) {
        final j = value(key);
        final p = ProductoCreadoPayload.fromJson(j);
        expect(p.knowsOfferPrice, key != 'product_legacy');
        expect(
          ProductoCreadoPayload.fromJson(
            p.toJson(),
          ).variantes.first.offerPriceMinor,
          p.variantes.first.offerPriceMinor,
        );
        expect(
          (p.toJson()['variants'] as List).first.containsKey(
            'offer_price_minor',
          ),
          key != 'product_legacy',
        );
        expect(
          p.withKnownMinimumStock().variantes.first.offerPriceMinor,
          p.variantes.first.offerPriceMinor,
        );
        expect(
          p.withKnownSuppliers().variantes.first.knowsOfferPrice,
          p.knowsOfferPrice,
        );
      }
    },
  );
  test(
    'bases: promoción explícita, no retroceso de conocimiento incluso null',
    () {
      final legacy = ProductoCreadoPayload.fromJson(value('product_legacy'));
      final known = ProductoCreadoPayload.fromJson(value('product_null'));
      expect(ProductoActualizadoPayload.sameEditingBase(legacy, known), isTrue);
      expect(
        ProductoActualizadoPayload.sameEditingBase(known, legacy),
        isFalse,
      );
    },
  );
  for (final invalid in fixture['invalid_offers'] as List) {
    test('producto rechaza oferta $invalid', () {
      final j = value('product');
      obj((j['variants'] as List).first);
      (j['variants'] as List).first['offer_price_minor'] = invalid;
      expect(() => ProductoCreadoPayload.fromJson(j), throwsA(anything));
    });
  }
  test(
    'venta v2 y legado conservan precio/costo/origen acreditado en round-trip',
    () {
      for (final key in ['sale', 'sale_legacy']) {
        final p = VentaConfirmadaPayload.fromJson(value(key));
        final again = VentaConfirmadaPayload.fromJson(p.toJson());
        expect(again.toJson(), p.toJson());
        expect(again.lines.first.snapshot.unitPriceMinor, 2000);
        expect(again.pricingContractVersion, key == 'sale' ? 2 : null);
        expect(
          again.lines.first.snapshot.effectivePriceSource,
          key == 'sale' ? 'offer' : null,
        );
      }
    },
  );
  final invalidFields = obj(fixture['invalid_snapshot_fields']);
  for (final field in invalidFields.entries) {
    for (final invalid in field.value as List) {
      test('venta rechaza ${field.key}=$invalid', () {
        final j = value('sale');
        (j['lines'] as List).first['snapshot'][field.key] = invalid;
        expect(() => VentaConfirmadaPayload.fromJson(j), throwsA(anything));
      });
    }
  }
  test(
    'persistencia SQLite de recepción v2 y replay idempotente conservan snapshot',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final product = value('product');
      final productId =
          (value('sale')['lines'] as List).first['product_id'] as String;
      final event = SyncEvent(
        eventId: '00000000-0000-4000-8000-000000000005',
        aggregateType: 'product',
        aggregateId: productId,
        eventType: 'producto_creado',
        deviceId: 'd',
        userId: 'u',
        createdAtLocal: DateTime.utc(2026),
        baseVersion: 1,
        payload: product,
      );
      final store = DriftProductoProjectionStore(productoDao: db.productoDao);
      await ProductoEventHandler(
        store,
        variantInventoryMemoryStore: DriftVariantInventoryMemoryStore(
          dao: db.variantInventoryMemoryDao,
        ),
      ).applyProductoCreado(event);
      // lastEventId ofrece la presencia; el evento se almacena como lo hace el event store.
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              eventId: event.eventId,
              aggregateType: 'product',
              aggregateId: productId,
              eventType: 'producto_creado',
              deviceId: 'd',
              userId: 'u',
              createdAtLocal: event.createdAtLocal,
              payload: jsonEncode(product),
            ),
          );
      expect(
        (await store.snapshot(productId)).variantes.first.offerPriceMinor,
        2000,
      );
      final original = await db.select(db.productVariants).getSingle();
      final updates = <SyncEvent>[];
      for (final price in [null, 1500]) {
        final state = value('product');
        (state['variants'] as List).first['offer_price_minor'] = price;
        final current = await store.findProductById(productId);
        final change = SyncEvent(
          eventId: price == null
              ? '00000000-0000-4000-8000-000000000040'
              : '00000000-0000-4000-8000-000000000041',
          aggregateType: 'product',
          aggregateId: productId,
          eventType: 'producto_actualizado',
          deviceId: 'd',
          userId: 'u',
          createdAtLocal: DateTime.utc(2026),
          baseVersion: current!.version,
          payload: {},
        );
        await db.transaction(
          () =>
              store.applyUpdate(change, ProductoCreadoPayload.fromJson(state)),
        );
        updates.add(change);
      }
      for (var i = updates.length - 1; i >= 0; i--) {
        await db.transaction(
          () => store.applyUpdate(
            updates[i],
            ProductoCreadoPayload.fromJson(product),
            restore: true,
            baseEventId: i == 0 ? event.eventId : updates[i - 1].eventId,
          ),
        );
      }
      expect(
        (await db.select(db.productVariants).getSingle()).toJson(),
        original.toJson(),
      );
      expect((await store.snapshot(productId)).knowsOfferPrice, isTrue);
      final payload = VentaConfirmadaPayload.fromJson(value('sale'));
      final saleEvent = SyncEvent(
        eventId: '00000000-0000-4000-8000-000000000030',
        aggregateType: 'sale',
        aggregateId: '00000000-0000-4000-8000-000000000002',
        eventType: 'venta_confirmada',
        deviceId: 'd',
        userId: 'u',
        createdAtLocal: DateTime.utc(2026),
        baseVersion: 1,
        payload: payload.toJson(),
      );
      final sales = DriftConfirmedSaleStore(db);
      await sales.apply(saleEvent, payload);
      await sales.apply(saleEvent, payload);
      final row = await db.select(db.saleItems).getSingle();
      expect(row.offerPriceMinorSnapshot, 2000);
      expect(row.standardCostMinorSnapshot, 1000);
      expect(row.priceConfigurationEventId, event.eventId);
      expect(
        (await db.saleDao.items(
          saleEvent.aggregateId,
        )).single.snapshot.toJson(),
        payload.lines.single.snapshot.toJson(),
      );
      expect((await db.select(db.sales).getSingle()).pricingMode, 'offer');
      expect(await db.select(db.salePayments).get(), hasLength(1));
    },
  );
}
