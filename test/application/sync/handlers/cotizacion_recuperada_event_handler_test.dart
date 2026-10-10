import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_recuperada_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import '../../../support/quotation_harness.dart';

void main() {
  late QuotationHarness h;
  late RecuperarCotizacionCommand c;
  late SyncEvent event;
  late CotizacionRecuperadaPayload payload;
  setUp(() async {
    h = QuotationHarness(mode: AppMode.serverSync);
    await h.seed();
    await h.add();
    final save = await h.intent();
    await h.service().guardar(save);
    await h.drafts.limpiar(LimpiarVentaBorradorCommand(saleId: save.saleId));
    c = RecuperarCotizacionCommand(
      quotationId: save.quotationId,
      expectedQuotationEventId: save.eventId,
    );
    await h.service().recuperar(c);
    event = (await h.db.quotationDao.findEventById(c.eventId))!;
    payload = CotizacionRecuperadaPayload.fromJson(event.payload);
    await (h.db.delete(
      h.db.eventRefs,
    )..where((t) => t.eventId.equals(c.eventId))).go();
    await (h.db.delete(
      h.db.events,
    )..where((t) => t.eventId.equals(c.eventId))).go();
    await h.db
        .update(h.db.quotations)
        .write(
          QuotationsCompanion(
            version: const Value(1),
            lastEventId: Value(save.eventId),
            currentSaleId: Value(save.saleId),
          ),
        );
  });
  tearDown(() => h.dispose());
  Future<void> append(SyncEvent e) =>
      h.events.appendAndApply(e, refs: payload.refs(c.quotationId));
  test(
    'P12: el vínculo sólo verifica el borrador capturado, sin consultar catálogo',
    () async {
      await h.db
          .update(h.db.productVariants)
          .write(
            const ProductVariantsCompanion(
              active: Value(false),
              salePriceMinor: Value(99999),
            ),
          );
      final before = await h.contents(
        excluded: {'quotations', 'events', 'event_refs'},
      );
      await append(event);
      expect(
        await h.contents(excluded: {'quotations', 'events', 'event_refs'}),
        before,
      );
      expect(
        (await h.db.quotationDao.findById(c.quotationId))!.currentSaleId,
        c.saleId,
      );
    },
  );
  test(
    'P13: sobre remoto, base, propietario, fecha y tipo rechazados atómicamente',
    () async {
      final before = await h.contents();
      for (final e in [
        event.copyWith(serverSequence: 1),
        event.copyWith(baseServerSequence: 1),
        event.copyWith(baseVersion: 0),
        event.copyWith(baseVersion: 2),
        event.copyWith(userId: 'other'),
        event.copyWith(deviceId: 'other'),
        event.copyWith(aggregateType: 'sale'),
        event.copyWith(
          createdAtLocal: c.recoveredAtLocal.add(const Duration(seconds: 1)),
        ),
      ]) {
        await expectLater(append(e), throwsStateError);
        expect(await h.contents(), before);
      }
    },
  );
  for (final change in [
    'total',
    'version',
    'created',
    'last',
    'owner',
    'confirmed',
    'quantity',
    'price',
    'lineVersion',
    'order',
    'eventOwner',
    'eventSnapshot',
    'eventVersion',
    'missingEvent',
    'selection',
  ]) {
    test('P12/P13: vínculo rechaza borrador que no acredita $change', () async {
      switch (change) {
        case 'total':
          await h.db
              .update(h.db.sales)
              .write(const SalesCompanion(totalMinor: Value(1)));
        case 'version':
          await h.db
              .update(h.db.sales)
              .write(const SalesCompanion(version: Value(2)));
        case 'created':
          await h.db
              .update(h.db.sales)
              .write(const SalesCompanion(createdEventId: Value('other')));
        case 'last':
          await h.db
              .update(h.db.sales)
              .write(const SalesCompanion(lastEventId: Value('other')));
        case 'owner':
          await h.db
              .update(h.db.sales)
              .write(const SalesCompanion(userId: Value('other')));
        case 'confirmed':
          await h.db
              .update(h.db.sales)
              .write(const SalesCompanion(status: Value('confirmada')));
        case 'quantity':
          await h.db
              .update(h.db.saleItems)
              .write(const SaleItemsCompanion(quantity: Value(2)));
        case 'price':
          await h.db
              .update(h.db.saleItems)
              .write(const SaleItemsCompanion(unitPriceMinor: Value(9999)));
        case 'lineVersion':
          await h.db
              .update(h.db.saleItems)
              .write(const SaleItemsCompanion(version: Value(2)));
        case 'order':
          await h.db
              .update(h.db.saleItems)
              .write(const SaleItemsCompanion(sortOrder: Value(1)));
        case 'eventOwner':
          await (h.db.update(h.db.events)
                ..where((t) => t.eventId.equals(payload.draftCreatedEventId)))
              .write(const EventsCompanion(userId: Value('other')));
        case 'eventSnapshot':
          await (h.db.update(h.db.events)
                ..where((t) => t.eventId.equals(payload.draftCreatedEventId)))
              .write(const EventsCompanion(payload: Value('{}')));
        case 'eventVersion':
          await (h.db.update(h.db.events)
                ..where((t) => t.eventId.equals(payload.draftCreatedEventId)))
              .write(const EventsCompanion(baseVersion: Value(1)));
        case 'missingEvent':
          await (h.db.delete(
            h.db.events,
          )..where((t) => t.eventId.equals(payload.draftCreatedEventId))).go();
        case 'selection':
          await h.db
              .update(h.db.quotationItems)
              .write(const QuotationItemsCompanion(quantity: Value(2)));
      }
      final before = await h.contents();
      await expectLater(append(event), throwsA(anything));
      expect(await h.contents(), before);
    });
  }
  for (final collision in ['sale', 'line', 'event']) {
    test(
      'P13: comando protege identidad ocupada de $collision antes de upsert',
      () async {
        final original = (await h.db.select(h.db.saleItems).get()).single;
        await h.db.delete(h.db.saleItems).go();
        await h.db.delete(h.db.sales).go();
        await (h.db.delete(
          h.db.events,
        )..where((t) => t.eventId.equals(payload.draftCreatedEventId))).go();
        if (collision == 'event') {
          await h.db
              .into(h.db.events)
              .insert(
                EventsCompanion.insert(
                  eventId: payload.draftCreatedEventId,
                  aggregateType: 'foreign',
                  aggregateId: 'foreign',
                  eventType: 'fixture',
                  userId: 'other',
                  deviceId: 'other',
                  createdAtLocal: c.recoveredAtLocal,
                  payload: '{}',
                ),
              );
        } else {
          final foreign = collision == 'sale'
              ? c.saleId
              : '00000000-0000-4000-8000-000000000080';
          await h.db
              .into(h.db.sales)
              .insert(
                SalesCompanion.insert(
                  id: foreign,
                  userId: 'other',
                  deviceId: 'other',
                  totalMinor: 3500,
                  createdAtLocal: c.recoveredAtLocal,
                  updatedAtLocal: c.recoveredAtLocal,
                ),
              );
          if (collision == 'line') {
            await h.db
                .into(h.db.saleItems)
                .insert(original.copyWith(saleId: foreign));
          }
        }
        final before = await h.contents();
        await expectLater(h.service().recuperar(c), throwsStateError);
        expect(await h.contents(), before);
      },
    );
  }
  test(
    'P13: revisión alterada al insertar vínculo revierte todas las líneas/eventos',
    () async {
      await h.db.delete(h.db.saleItems).go();
      await h.db.delete(h.db.sales).go();
      await (h.db.delete(
        h.db.events,
      )..where((t) => t.eventId.equals(payload.draftCreatedEventId))).go();
      await h.db.customStatement(
        "CREATE TRIGGER change_recovery_base AFTER INSERT ON events WHEN NEW.event_type = 'cotizacion_recuperada' BEGIN UPDATE quotations SET version=version+1,last_event_id='another' WHERE id=NEW.aggregate_id; END",
      );
      final before = await h.contents();
      await expectLater(h.service().recuperar(c), throwsStateError);
      expect(await h.contents(), before);
    },
  );
  test(
    'P17/P18: confirmado con cotización atrasada nunca se vuelve a vincular',
    () async {
      await h.confirm();
      final before = await h.contents();
      await expectLater(append(event), throwsStateError);
      expect(await h.contents(), before);
    },
  );
}
