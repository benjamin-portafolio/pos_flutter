import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/guardar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/cotizaciones/quotation_already_linked_exception.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_guardada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/quotation_repository_impl.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_status.dart';
import '../../../support/quotation_harness.dart';

void main() {
  late QuotationHarness h;
  setUp(() async {
    h = QuotationHarness();
    await h.seed();
  });
  tearDown(() => h.dispose());
  const unchangedTables = {
    'quotations',
    'quotation_items',
    'events',
    'event_refs',
  };
  GuardarCotizacionCommand copy(
    GuardarCotizacionCommand c, {
    String? saleId,
    String? revision,
    String? quotationId,
    String? eventId,
    DateTime? issuedAt,
  }) => GuardarCotizacionCommand(
    saleId: saleId ?? c.saleId,
    expectedDraftEventId: revision ?? c.expectedDraftEventId,
    quotationId: quotationId ?? c.quotationId,
    eventId: eventId ?? c.eventId,
    issuedAtLocal: issuedAt ?? c.issuedAtLocal,
  );

  for (final mode in AppMode.values) {
    test(
      'C02/C08/C32/C33: snapshots y refs en ${mode.name}, sin movimientos',
      () async {
        h.config.update(h.config.config.copyWith(mode: mode));
        for (final id in [
          QuotationHarness.directId,
          QuotationHarness.recipeId,
          QuotationHarness.measuredId,
        ]) {
          await h.add(id);
        }
        final command = await h.intent();
        // Guardar conserva precios de captura incluso si cambia el catálogo.
        await h.db
            .update(h.db.productVariants)
            .write(
              const ProductVariantsCompanion(salePriceMinor: Value(99999)),
            );
        final before = await h.contents(excluded: unchangedTables);
        final result = await h.service().guardar(command);
        expect(await h.contents(excluded: unchangedTables), before);
        final quotation = (await h.repository.findById(result.quotationId))!;
        expect(quotation.status, QuotationStatus.enVenta);
        expect(quotation.currentSaleId, command.saleId);
        expect(quotation.sourceDraftEventId, command.expectedDraftEventId);
        expect(quotation.issuedAtLocal, command.issuedAtLocal);
        final estimate = await h.repository.estimate(quotation);
        expect(estimate.currency, 'MXN');
        expect(estimate.lines.map((line) => line.unitPriceMinor), [
          99999,
          99999,
          99999,
        ]);
        final measured = quotation.items.last;
        expect(measured.measuredQuantityAtomic, 750);
        expect(measured.unitAtomicFactor, 1000);
        expect(measured.unitCode, 'kg');
        final sourceIds = (await h.db.saleDao.items(
          command.saleId,
        )).map((item) => item.id).toSet();
        expect(
          quotation.items.any((item) => sourceIds.contains(item.id)),
          isFalse,
        );
        expect(() => quotation.items.clear(), throwsUnsupportedError);
        final event = (await h.db.eventDao.obtenerEventoPorId(result.eventId))!;
        expect(event.deliveryStatus, 'not_required');
        expect(event.baseVersion, 0);
        expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
        final refs = await (h.db.select(
          h.db.eventRefs,
        )..where((t) => t.eventId.equals(result.eventId))).get();
        expect(refs.length, mode == AppMode.standalone ? 0 : 5);
        if (mode == AppMode.serverSync) {
          expect(refs.map((r) => '${r.refType}:${r.relationship}'), [
            'quotation:affects',
            'quotation_item:affects',
            'quotation_item:affects',
            'quotation_item:affects',
            'sale:uses',
          ]);
        }
        // La clasificación del store prevalece sobre delivery_status solicitado.
        final local = (await h.db.quotationDao.findEventById(result.eventId))!;
        await (h.db.delete(
          h.db.eventRefs,
        )..where((t) => t.eventId.equals(result.eventId))).go();
        await (h.db.delete(
          h.db.events,
        )..where((t) => t.eventId.equals(result.eventId))).go();
        await h.events.appendAndApply(
          local.copyWith(deliveryStatus: 'pending'),
          refs: CotizacionGuardadaPayload.fromJson(
            local.payload,
          ).refs(result.quotationId),
        );
        expect(
          (await h.db.eventDao.obtenerEventoPorId(
            result.eventId,
          ))!.deliveryStatus,
          'not_required',
        );
        expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
      },
    );
  }

  test(
    'C01/C03: inexistente, sin líneas activas y contexto inválido no escriben',
    () async {
      final missing = GuardarCotizacionCommand(
        saleId: 'missing',
        expectedDraftEventId: 'missing',
      );
      final before = await h.contents();
      await expectLater(h.service().guardar(missing), throwsStateError);
      expect(await h.contents(), before);
      await h.add();
      final command = await h.intent();
      await h.db
          .update(h.db.saleItems)
          .write(const SaleItemsCompanion(active: Value(false)));
      await h.db
          .update(h.db.sales)
          .write(const SalesCompanion(totalMinor: Value(0)));
      final emptyBefore = await h.contents();
      await expectLater(h.service().guardar(copy(command)), throwsStateError);
      await expectLater(
        h
            .service(
              owner: const LocalCommandContext(userId: '', deviceId: 'x'),
            )
            .guardar(command),
        throwsFormatException,
      );
      expect(await h.contents(), emptyBefore);
    },
  );

  test('C03: propiedad, revisión y total obsoletos no escriben', () async {
    await h.add();
    final command = await h.intent();
    final before = await h.contents();
    for (final owner in [
      const LocalCommandContext(
        userId: 'foreign',
        deviceId: 'quotation-tablet',
      ),
      const LocalCommandContext(userId: 'quotation-user', deviceId: 'foreign'),
    ]) {
      await expectLater(
        h.service(owner: owner).guardar(command),
        throwsStateError,
      );
    }
    for (final invalid in [copy(command, revision: 'old')]) {
      await expectLater(h.service().guardar(invalid), throwsStateError);
    }
    expect(await h.contents(), before);
    for (final status in ['confirmada', 'descartada']) {
      await h.db
          .update(h.db.sales)
          .write(SalesCompanion(status: Value(status)));
      await expectLater(h.service().guardar(command), throwsStateError);
    }
    await h.db
        .update(h.db.sales)
        .write(
          const SalesCompanion(status: Value('borrador'), active: Value(false)),
        );
    await expectLater(h.service().guardar(command), throwsStateError);
    expect(await h.db.select(h.db.quotations).get(), isEmpty);
  });

  test(
    'C03: importe de línea corrupto, rango y suma inválidos se rechazan',
    () async {
      await h.add();
      final command = await h.intent();
      await h.db
          .update(h.db.saleItems)
          .write(const SaleItemsCompanion(totalMinor: Value(1)));
      await expectLater(h.service().guardar(command), throwsStateError);
      await h.db
          .update(h.db.saleItems)
          .write(const SaleItemsCompanion(totalMinor: Value(3500)));
      await h.db
          .update(h.db.sales)
          .write(const SalesCompanion(totalMinor: Value(1)));
      await expectLater(h.service().guardar(copy(command)), throwsStateError);
      await h.db.customStatement('PRAGMA ignore_check_constraints = ON');
      await h.db
          .update(h.db.saleItems)
          .write(const SaleItemsCompanion(quantity: Value(9007199254740992)));
      await expectLater(h.service().guardar(command), throwsFormatException);
      expect(await h.db.select(h.db.quotations).get(), isEmpty);
    },
  );

  test(
    'C04/C05: reintento concurrente e identidades estables, colisiones rechazadas',
    () async {
      await h.add();
      final command = await h.intent();
      final results = await Future.wait([
        h.service().guardar(command),
        h.service().guardar(copy(command)),
      ]);
      expect(results.map((r) => r.quotationId).toSet(), {command.quotationId});
      expect(results.map((r) => r.issuedAtLocal).toSet(), {
        command.issuedAtLocal,
      });
      final before = await h.contents();
      for (final collision in [
        copy(command, revision: 'old'),
        copy(command, saleId: 'other'),
        copy(command, quotationId: 'other'),
        copy(
          command,
          issuedAt: command.issuedAtLocal.add(const Duration(seconds: 1)),
        ),
        copy(command, eventId: 'another-event'),
        copy(
          command,
          quotationId: 'another-quotation',
          eventId: QuotationHarness.configId,
        ),
      ]) {
        await expectLater(h.service().guardar(collision), throwsStateError);
      }
      final another = await h.intent();
      await expectLater(
        h.service().guardar(another),
        throwsA(
          isA<QuotationAlreadyLinkedException>().having(
            (e) => e.quotationId,
            'existente',
            command.quotationId,
          ),
        ),
      );
      expect(await h.contents(), before);
      expect(await h.db.select(h.db.quotations).get(), hasLength(1));
    },
  );

  test('C05: dos intenciones simultáneas no asocian dos documentos', () async {
    await h.add();
    final a = await h.intent();
    final b = await h.intent();
    Future<Object> attempt(GuardarCotizacionCommand c) async {
      try {
        return await h.service().guardar(c);
      } catch (e) {
        return e;
      }
    }

    final results = await Future.wait([attempt(a), attempt(b)]);
    expect(results.whereType<QuotationAlreadyLinkedException>(), hasLength(1));
    expect(await h.db.select(h.db.quotations).get(), hasLength(1));
  });

  for (final failure in ['segunda línea', 'después del handler']) {
    test(
      'C25: rollback de documento, líneas, evento, refs y vínculo ($failure)',
      () async {
        h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
        await h.add();
        await h.add(QuotationHarness.recipeId);
        final command = await h.intent();
        final before = await h.contents();
        if (failure == 'segunda línea') {
          await h.db.customStatement(
            "CREATE TRIGGER reject_quotation BEFORE INSERT ON quotation_items WHEN NEW.sort_order = 1 BEGIN SELECT RAISE(ABORT, 'injected'); END",
          );
        } else {
          h.failAfterSave = true;
        }
        await expectLater(h.service().guardar(command), throwsA(anything));
        expect(await h.contents(), before);
        if (failure == 'segunda línea') {
          await h.db.customStatement('DROP TRIGGER reject_quotation');
        } else {
          h.failAfterSave = false;
        }
        await h.service().guardar(command);
        expect(await h.db.select(h.db.quotationItems).get(), hasLength(2));
      },
    );
  }

  test(
    'C07/C25/C26/C27: limpieza revisada, rollback y replay conservan documento',
    () async {
      h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
      await h.add();
      final command = await h.intent();
      await h.service().guardar(command);
      final emitted = await h.contents(
        excluded: {'sales', 'sale_items', 'events', 'event_refs'},
      );
      final event = (await h.db.quotationDao.findEventById(command.eventId))!;
      final cleanup = LimpiarVentaBorradorCommand(
        saleId: command.saleId,
        expectedDraftEventId: command.expectedDraftEventId,
      );
      final originalLine = (await h.db.saleDao.items(command.saleId)).single;
      await h.drafts.actualizarProducto(
        ActualizarProductoBorradorCommand(
          saleItemId: originalLine.id,
          quantity: 2,
        ),
      );
      final before = await h.contents();
      await expectLater(h.drafts.limpiar(cleanup), throwsStateError);
      expect(await h.contents(), before);
      final current = await h.intent();
      final safe = LimpiarVentaBorradorCommand(
        saleId: current.saleId,
        expectedDraftEventId: current.expectedDraftEventId,
      );
      await h.db.customStatement(
        "CREATE TRIGGER reject_cleanup BEFORE DELETE ON sales BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(h.drafts.limpiar(safe), throwsA(anything));
      expect(await h.contents(), before);
      await h.db.customStatement('DROP TRIGGER reject_cleanup');
      await h.drafts.limpiar(safe);
      expect(
        (await h.repository.findById(command.quotationId))!.status,
        QuotationStatus.disponible,
      );
      expect(
        await h.contents(
          excluded: {'sales', 'sale_items', 'events', 'event_refs'},
        ),
        emitted,
      );
      await h.add();
      final next = await h.intent();
      await h.drafts.limpiar(
        cleanup,
      ); // Origen ausente: no-op; la nueva captura queda.
      await h.handler.apply(event);
      final retry = await h.service().guardar(command);
      expect(retry.quotationId, command.quotationId);
      expect(await h.db.saleDao.findById(next.saleId), isNotNull);
      expect(await h.db.saleDao.findById(command.saleId), isNull);
      expect(
        (await h.db.quotationDao.findById(command.quotationId))!.currentSaleId,
        command.saleId,
      );
      // Incluso si desaparece el catálogo, el documento completo se lee.
      await h.drafts.limpiar(LimpiarVentaBorradorCommand(saleId: next.saleId));
      await h.db.delete(h.db.recipeComponents).go();
      await h.db.delete(h.db.productVariants).go();
      await h.db.delete(h.db.products).go();
      expect(
        (await h.repository.findById(
          command.quotationId,
        ))!.items.single.productName,
        'Pan',
      );
    },
  );

  test(
    'C27: handler rechaza contenido distinto con el mismo eventId',
    () async {
      await h.add();
      final command = await h.intent();
      await h.service().guardar(command);
      final event = (await h.db.quotationDao.findEventById(command.eventId))!;
      final before = await h.contents();
      final changed =
          jsonDecode(jsonEncode(event.payload)) as Map<String, dynamic>;
      changed['lines'][0]['selection']['product_name_snapshot'] = 'Distinto';
      await expectLater(
        h.handler.apply(event.copyWith(payload: changed)),
        throwsStateError,
      );
      await expectLater(
        h.handler.apply(event.copyWith(eventId: 'other')),
        throwsStateError,
      );
      await expectLater(
        h.handler.apply(event.copyWith(deliveryStatus: 'pending')),
        throwsStateError,
      );
      await h.handler.apply(event);
      await h.handler.apply(event);
      expect(await h.contents(), before);
    },
  );

  test(
    'P05: retry de guardado rechaza selección alterada aun con mismo evento',
    () async {
      await h.add();
      final command = await h.intent();
      await h.service().guardar(command);
      final event = (await h.db.quotationDao.findEventById(command.eventId))!;
      final changed =
          jsonDecode(jsonEncode(event.payload)) as Map<String, dynamic>;
      changed['lines'][0]['selection']['quantity'] = 2;
      await (h.db.update(h.db.events)
            ..where((t) => t.eventId.equals(event.eventId)))
          .write(EventsCompanion(payload: Value(jsonEncode(changed))));
      final before = await h.contents();
      await expectLater(h.service().guardar(command), throwsStateError);
      expect(await h.contents(), before);
    },
  );

  test(
    'índices y FK protegen vínculo único, orden e integridad de líneas',
    () async {
      await h.add();
      final command = await h.intent();
      await h.service().guardar(command);
      final q = (await h.db.select(h.db.quotations).get()).single;
      await expectLater(
        h.db.into(h.db.quotations).insert(q.copyWith(id: 'duplicate')),
        throwsA(anything),
      );
      final item = (await h.db.select(h.db.quotationItems).get()).single;
      await expectLater(
        h.db
            .into(h.db.quotationItems)
            .insert(item.copyWith(id: 'duplicate-line')),
        throwsA(anything),
      );
      await expectLater(
        h.db
            .into(h.db.quotationItems)
            .insert(item.copyWith(id: 'orphan', quotationId: 'missing')),
        throwsA(anything),
      );
      await expectLater(h.db.delete(h.db.quotations).go(), throwsA(anything));
    },
  );

  test(
    'C21/C24/C33: cobro directo actualiza stream a Vendida y sólo venta es pending',
    () async {
      h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
      await h.add();
      await h.add(QuotationHarness.recipeId);
      final command = await h.intent();
      await h.service().guardar(command);
      final seen = <QuotationStatus>[];
      final subscription = h.repository.watchById(command.quotationId).listen((
        q,
      ) {
        if (q != null) seen.add(q.status);
      });
      await h.repository.watchById(command.quotationId).first;
      final sold = h.repository
          .watchById(command.quotationId)
          .firstWhere((q) => q?.status == QuotationStatus.vendida);
      final eventId = await h.confirm();
      expect((await sold)!.status, QuotationStatus.vendida);
      final pending = await h.db.eventDao.obtenerEventosPendientes();
      expect(pending.map((event) => event.eventId), [eventId]);
      final payload = VentaConfirmadaPayload.fromJson(
        jsonDecode(pending.single.payload) as Map<String, Object?>,
      );
      expect(payload.dependencyEventIds, isNot(contains(command.eventId)));
      expect(
        payload
            .refs(command.saleId)
            .any((ref) => ref.refType.startsWith('quotation')),
        isFalse,
      );
      expect(await h.db.select(h.db.salePayments).get(), hasLength(1));
      expect(await h.db.select(h.db.inventoryMovements).get(), hasLength(2));
      expect(
        (await h.db.select(h.db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        996,
      );
      for (final delivery in ['pending', 'conflict', 'rejected']) {
        await h.db.eventDao.actualizarEstadoSincronizacion(eventId, delivery);
        expect(
          (await h.repository.findById(command.quotationId))!.status,
          QuotationStatus.vendida,
        );
        expect(await h.repository.watchQuotations().first, isEmpty);
        expect(
          await h.repository.watchQuotations(onlyRecoverable: false).first,
          hasLength(1),
        );
      }
      final before = await h.contents();
      await h.handler.apply(
        (await h.db.quotationDao.findEventById(command.eventId))!,
      );
      await h.service().guardar(command);
      expect(await h.contents(), before);
      expect(seen, contains(QuotationStatus.vendida));
      await subscription.cancel();
    },
  );

  test(
    'repositorio observa limpieza, orden de emisión e ID y filtra propietario',
    () async {
      await h.add();
      final a = await h.intent();
      final first = copy(
        a,
        quotationId: 'a',
        issuedAt: DateTime.utc(2026, 10, 5),
      );
      await h.service().guardar(first);
      final available = h.repository
          .watchById(first.quotationId)
          .firstWhere((q) => q?.status == QuotationStatus.disponible);
      await h.drafts.limpiar(LimpiarVentaBorradorCommand(saleId: a.saleId));
      expect((await available)!.status, QuotationStatus.disponible);
      await h.add();
      final b = await h.intent();
      await h.service().guardar(
        copy(b, quotationId: 'b', issuedAt: first.issuedAtLocal),
      );
      expect((await h.repository.watchQuotations().first).map((q) => q.id), [
        'b',
        'a',
      ]);
      final foreign = QuotationRepositoryImpl(
        dao: h.db.quotationDao,
        validator: h.validator,
        userId: 'other',
        deviceId: h.context.deviceId,
      );
      expect(
        await foreign.watchQuotations(onlyRecoverable: false).first,
        isEmpty,
      );
      expect(await foreign.findById('a'), isNull);
      expect(await foreign.watchById('a').first, isNull);
    },
  );
}
