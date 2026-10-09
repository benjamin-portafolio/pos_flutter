import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/cotizaciones/quotation_recovery_identity.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_recuperada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/application/sync/quotation_recovery_line_exception.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_status.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/ventas/sale_status.dart';
import '../../../support/quotation_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuotationHarness h;
  setUp(() async {
    h = QuotationHarness();
    await h.seed();
  });
  tearDown(() => h.dispose());

  Future<RecuperarCotizacionCommand> available({bool all = false}) async {
    await h.add();
    if (all) {
      await h.add(QuotationHarness.recipeId);
      await h.add(QuotationHarness.measuredId);
    }
    final save = await h.intent();
    await h.service().guardar(save);
    await h.drafts.limpiar(
      LimpiarVentaBorradorCommand(
        saleId: save.saleId,
        expectedDraftEventId: save.expectedDraftEventId,
      ),
    );
    return RecuperarCotizacionCommand(
      quotationId: save.quotationId,
      expectedQuotationEventId: save.eventId,
    );
  }

  Future<RecuperarCotizacionCommand> next(String id) async =>
      RecuperarCotizacionCommand(
        quotationId: id,
        expectedQuotationEventId: (await h.db.quotationDao.findById(
          id,
        ))!.lastEventId!,
      );
  Future<void> clear(String id) =>
      h.drafts.limpiar(LimpiarVentaBorradorCommand(saleId: id));
  RecuperarCotizacionCommand copy(
    RecuperarCotizacionCommand c, {
    String? quotationId,
    String? revision,
    String? saleId,
    String? eventId,
    DateTime? time,
  }) => RecuperarCotizacionCommand(
    quotationId: quotationId ?? c.quotationId,
    expectedQuotationEventId: revision ?? c.expectedQuotationEventId,
    saleId: saleId ?? c.saleId,
    eventId: eventId ?? c.eventId,
    recoveredAtLocal: time ?? c.recoveredAtLocal,
  );
  const changed = {'quotations', 'sales', 'sale_items', 'events', 'event_refs'};
  Future<Map<String, Object?>> documentContents() async {
    final contents = await h.contents(
      excluded: h.db.allTables
          .map((t) => t.actualTableName)
          .where((t) => t != 'quotations' && t != 'quotation_items')
          .toSet(),
    );
    // El vínculo y su revisión sí cambian; el resto del documento es emitido.
    for (final row in contents['quotations'] as List<Map<String, Object?>>) {
      row.remove('current_sale_id');
      row.remove('version');
      row.remove('last_event_id');
    }
    return contents;
  }

  for (final mode in AppMode.values) {
    test(
      'C14/C15/C30/C32/C33: recuperación completa y sin movimientos $mode',
      () async {
        h.config.update(
          h.config.config.copyWith(mode: mode, cashEnabled: true),
        );
        final c = await available(all: true);
        final issued = (await h.db.quotationDao.items(
          c.quotationId,
        )).map((i) => i.selection.toJson()).toList();
        await h.db
            .update(h.db.productVariants)
            .write(
              const ProductVariantsCompanion(
                salePriceMinor: Value(99999),
                standardCostMinor: Value(1234),
              ),
            );
        await h.db
            .update(h.db.products)
            .write(const ProductsCompanion(name: Value('Nombre nuevo')));
        for (final variantId in [
          QuotationHarness.directId,
          QuotationHarness.recipeId,
          QuotationHarness.measuredId,
        ]) {
          await (h.db.update(h.db.productVariants)
                ..where((t) => t.id.equals(variantId)))
              .write(ProductVariantsCompanion(name: Value('Nueva $variantId')));
        }
        final before = await h.contents(excluded: changed);
        final results = await Future.wait([
          h.service().recuperar(c),
          h.service().recuperar(c),
        ]);
        expect(results.map((r) => r.saleId), [c.saleId, c.saleId]);
        expect(results.first.continued, isFalse);
        expect(results.last.continued, isTrue);
        expect(results.first.draftAvailable, isTrue);
        expect(await h.contents(excluded: changed), before);
        final q = (await h.db.quotationDao.findById(c.quotationId))!;
        final s = (await h.db.saleDao.findById(c.saleId))!;
        expect(q.version, 2);
        expect(q.currentSaleId, c.saleId);
        expect(q.lastEventId, c.eventId);
        expect(s.version, 3);
        expect(s.status, SaleStatus.borrador);
        expect(
          s.lastEventId,
          QuotationRecoveryIdentity.draftEvent(
            c.eventId,
            c.saleId,
            (await h.db.quotationDao.items(q.id)).last.id,
          ),
        );
        final lines = await h.db.saleDao.items(c.saleId);
        expect(lines.map((i) => i.snapshot.unitPriceMinor), [
          99999,
          99999,
          99999,
        ]);
        expect(lines.map((i) => i.snapshot.standardCostMinor), [
          1234,
          1234,
          1234,
        ]);
        expect(lines.map((i) => i.snapshot.productName).toSet(), {
          'Nombre nuevo',
        });
        expect(
          (await h.db.quotationDao.items(
            c.quotationId,
          )).map((i) => i.selection.toJson()).toList(),
          issued,
        );
        expect(lines.map((i) => i.version), [1, 1, 1]);
        final quotationLines = await h.db.quotationDao.items(q.id);
        expect(
          lines.map((i) => i.id),
          quotationLines.map(
            (i) => QuotationRecoveryIdentity.saleItem(c.saleId, i.id),
          ),
        );
        expect(
          lines.any((i) => quotationLines.any((q) => q.id == i.id)),
          isFalse,
        );
        expect(
          (await h.repository.findById(q.id))!.status,
          QuotationStatus.enVenta,
        );
        final event = (await h.db.quotationDao.findEventById(c.eventId))!;
        expect(event.baseVersion, 1);
        expect(event.aggregateType, 'quotation');
        expect(event.deliveryStatus, 'not_required');
        expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
        final payload = CotizacionRecuperadaPayload.fromJson(event.payload);
        final refs = await (h.db.select(
          h.db.eventRefs,
        )..where((t) => t.eventId.equals(c.eventId))).get();
        expect(
          refs.length,
          mode == AppMode.standalone ? 0 : payload.refs(q.id).length,
        );
        if (mode == AppMode.serverSync) {
          expect(
            refs
                .map((r) => '${r.refType}:${r.refId}:${r.relationship}')
                .toSet(),
            payload
                .refs(q.id)
                .map((r) => '${r.refType}:${r.refId}:${r.relationship}')
                .toSet(),
          );
        }
        // Reinsertar solicitando pending prueba la clasificación explícita del store.
        await (h.db.delete(
          h.db.eventRefs,
        )..where((t) => t.eventId.equals(c.eventId))).go();
        await (h.db.delete(
          h.db.events,
        )..where((t) => t.eventId.equals(c.eventId))).go();
        await h.events.appendAndApply(
          event.copyWith(deliveryStatus: 'pending'),
          refs: payload.refs(q.id),
        );
        expect(
          (await h.db.eventDao.obtenerEventoPorId(c.eventId))!.deliveryStatus,
          'not_required',
        );
        expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
        // Sin sesión de caja se pudo recuperar; cobrar conserva la restricción existente.
        final beforeCharge = await h.contents();
        await expectLater(h.confirm(), throwsStateError);
        expect(await h.contents(), beforeCharge);
      },
    );

    test(
      'C14/C20/C29: continuación y reintentos conservan ediciones $mode',
      () async {
        h.config.update(h.config.config.copyWith(mode: mode));
        await h.add();
        final save = await h.intent();
        await h.service().guardar(save);
        final originalLine = (await h.db.saleDao.items(save.saleId)).single;
        await h.drafts.actualizarProducto(
          ActualizarProductoBorradorCommand(
            saleItemId: originalLine.id,
            quantity: 2,
          ),
        );
        final beforeOrigin = await h.contents();
        final continued = await h.service().recuperar(
          RecuperarCotizacionCommand(
            quotationId: save.quotationId,
            expectedQuotationEventId: save.eventId,
          ),
        );
        expect(continued.saleId, save.saleId);
        expect(continued.eventId, isNull);
        expect(await h.contents(), beforeOrigin);
        await clear(save.saleId);
        final c = await next(save.quotationId);
        final twin = await next(save.quotationId);
        final results = await Future.wait([
          h.service().recuperar(c),
          h.service().recuperar(twin),
        ]);
        expect(results.map((r) => r.saleId), [c.saleId, c.saleId]);
        final line = (await h.db.saleDao.items(c.saleId)).single;
        await h.drafts.actualizarProducto(
          ActualizarProductoBorradorCommand(saleItemId: line.id, quantity: 3),
        );
        // Incluso con catálogo retirado se continúa, sin copiar ni revalidar captura.
        await h.db
            .update(h.db.productVariants)
            .write(const ProductVariantsCompanion(active: Value(false)));
        final edited = await h.contents();
        expect((await h.service().recuperar(copy(c))).saleId, c.saleId);
        expect(
          (await h.service().recuperar(await next(c.quotationId))).saleId,
          c.saleId,
        );
        await h.recoveryHandler.apply(
          (await h.db.quotationDao.findEventById(c.eventId))!,
        );
        expect(await h.contents(), edited);
        expect(
          (await h.db.quotationDao.items(
            c.quotationId,
          )).single.selection.quantity,
          1,
        );
      },
    );

    for (final method in ['cash', 'transfer', 'credit']) {
      test(
        'C21/C23/C24/C29/C31/C33: cobro existente $method en $mode',
        () async {
          h.config.update(
            h.config.config.copyWith(mode: mode, cashEnabled: true),
          );
          final clienteId = method == 'credit' ? await h.customer() : null;
          final c = await available(all: true);
          final documentBefore = await documentContents();
          await h.service().recuperar(c);
          final line = (await h.db.saleDao.items(c.saleId)).first;
          await h.drafts.actualizarProducto(
            ActualizarProductoBorradorCommand(saleItemId: line.id, quantity: 2),
          );
          await h.cash.abrir(
            const AbrirCajaCommand(
              sessionId: '00000000-0000-4000-8000-000000000090',
              openingMinor: 0,
            ),
          );
          final confirmation = await h.confirm(
            method: method,
            clienteId: clienteId,
          );
          final sale = (await h.db.saleDao.findById(c.saleId))!;
          expect(sale.status, SaleStatus.confirmada);
          expect(sale.totalMinor, 16901);
          final payments = await h.db.select(h.db.salePayments).get();
          final debts = await h.db.select(h.db.creditSales).get();
          expect(payments.length, method == 'credit' ? 0 : 1);
          expect(debts.length, method == 'credit' ? 1 : 0);
          if (payments.isNotEmpty) {
            expect(payments.single.method, method);
            expect(payments.single.amountMinor, 16901);
          }
          if (debts.isNotEmpty) expect(debts.single.amountMinor, 16901);
          expect(
            (await h.db.select(h.db.inventoryMovements).get()).map(
              (m) => m.quantityDeltaAtomic,
            ),
            [-2, -3],
          );
          expect(
            (await h.db.select(h.db.inventoryBalances).get())
                .single
                .quantityOnHandAtomic,
            995,
          );
          final cash = await (h.db.select(
            h.db.cashMovements,
          )..where((t) => t.salePaymentId.isNotNull())).get();
          expect(cash.length, method == 'cash' ? 1 : 0);
          final payload = VentaConfirmadaPayload.fromJson(
            (await h.db.quotationDao.findEventById(confirmation))!.payload,
          );
          expect(payload.dependencyEventIds, isNot(contains(c.eventId)));
          expect(
            payload.dependencyEventIds,
            isNot(contains(c.expectedQuotationEventId)),
          );
          expect(
            payload
                .refs(c.saleId)
                .any((r) => r.refType.startsWith('quotation')),
            isFalse,
          );
          expect(payload.lines.map((l) => l.snapshot.unitPriceMinor), [
            3500,
            2400,
            10001,
          ]);
          final pending = await h.db.eventDao.obtenerEventosPendientes();
          expect(
            pending.any((e) => e.eventType.startsWith('cotizacion')),
            isFalse,
          );
          expect(
            pending.any((e) => e.eventId == confirmation),
            mode == AppMode.serverSync,
          );
          for (final status in ['pending', 'conflict', 'rejected']) {
            await h.db.eventDao.actualizarEstadoSincronizacion(
              confirmation,
              status,
            );
            expect(
              (await h.repository.findById(c.quotationId))!.status,
              QuotationStatus.vendida,
            );
            final before = await h.contents();
            await expectLater(
              h.service().recuperar(await next(c.quotationId)),
              throwsStateError,
            );
            await expectLater(h.service().recuperar(c), throwsStateError);
            await h.recoveryHandler.apply(
              (await h.db.quotationDao.findEventById(c.eventId))!,
            );
            await expectLater(
              h.confirm(method: method, clienteId: clienteId, saleId: c.saleId),
              throwsStateError,
            );
            expect(await h.contents(), before);
          }
          expect(await documentContents(), documentBefore);
          expect(
            (await h.repository.estimate(
              (await h.repository.findById(c.quotationId))!,
            )).totalMinor,
            13401,
          );
        },
      );
    }
  }

  test(
    'C16: configuración directa y receta vigente, y revalidación al cobrar',
    () async {
      final c = await available(all: true);
      final quoted = {
        for (final item in await h.db.quotationDao.items(c.quotationId))
          item.selection.variantId: await h.products
              .consumptionConfigurationKey(item.selection.variantId),
      };
      await (h.db.update(h.db.productVariants)
            ..where((t) => t.id.equals(QuotationHarness.directId)))
          .write(const ProductVariantsCompanion(inventoryItemId: Value(null)));
      await h.db
          .into(h.db.recipeComponents)
          .insert(
            RecipeComponentsCompanion.insert(
              variantId: QuotationHarness.directId,
              inventoryItemId: QuotationHarness.resourceId,
              quantityAtomic: 2,
            ),
          );
      await (h.db.update(h.db.recipeComponents)
            ..where((t) => t.variantId.equals(QuotationHarness.recipeId)))
          .write(const RecipeComponentsCompanion(quantityAtomic: Value(5)));
      final before = await h.contents(excluded: changed);
      await h.service().recuperar(c);
      expect(await h.contents(excluded: changed), before);
      final lines = await h.db.saleDao.items(c.saleId);
      for (final line in lines.take(2)) {
        expect(
          line.snapshot.consumptionConfigurationKey,
          await h.products.consumptionConfigurationKey(line.snapshot.variantId),
        );
        expect(
          line.snapshot.consumptionConfigurationKey,
          isNot(quoted[line.snapshot.variantId]),
        );
      }
      await (h.db.update(h.db.recipeComponents)
            ..where((t) => t.variantId.equals(QuotationHarness.recipeId)))
          .write(const RecipeComponentsCompanion(quantityAtomic: Value(6)));
      final changedAgain = await h.contents();
      await expectLater(h.confirm(), throwsStateError);
      expect(await h.contents(), changedAgain);
      await (h.db.update(h.db.recipeComponents)
            ..where((t) => t.variantId.equals(QuotationHarness.recipeId)))
          .write(const RecipeComponentsCompanion(quantityAtomic: Value(5)));
      await h.confirm();
      expect(
        (await h.db.select(h.db.inventoryMovements).get()).map(
          (m) => m.quantityDeltaAtomic,
        ),
        [-2, -5],
      );
    },
  );

  for (final empty in [true, false]) {
    test(
      'C19: otro borrador ${empty ? 'vacío' : 'con líneas'} no se pisa',
      () async {
        final c = await available();
        await h.add();
        final other = (await h.db.saleDao.findDraft(
          h.context.userId,
          h.context.deviceId,
        ))!;
        if (empty) {
          await (h.db.delete(
            h.db.saleItems,
          )..where((t) => t.saleId.equals(other.id))).go();
          await (h.db.update(h.db.sales)..where((t) => t.id.equals(other.id)))
              .write(const SalesCompanion(totalMinor: Value(0)));
        }
        final before = await h.contents();
        await expectLater(h.service().recuperar(c), throwsStateError);
        expect(await h.contents(), before);
        expect(
          (await h.repository.findById(c.quotationId))!.status,
          QuotationStatus.disponible,
        );
        await clear(other.id);
        expect((await h.service().recuperar(c)).saleId, c.saleId);
      },
    );
  }

  for (final change in [
    'mode',
    'unit',
    'factor',
    'dimension',
    'symbol',
    'code',
    'unitInactive',
    'unitMissing',
    'variantInactive',
    'variantMissing',
    'productInactive',
    'productMissing',
  ]) {
    test('C17/C18: $change rechaza por línea sin perder documento', () async {
      final c = await available(all: true);
      // Fallos físicos del catálogo se simulan sin FK para poder probar ausencia.
      await h.db.customStatement('PRAGMA foreign_keys = OFF');
      switch (change) {
        case 'mode':
          await (h.db.update(h.db.products)
                ..where((t) => t.id.equals(QuotationHarness.measuredProductId)))
              .write(
                const ProductsCompanion(
                  saleMode: Value('unit'),
                  saleUnitId: Value(null),
                  priceReferenceQuantityAtomic: Value(null),
                ),
              );
        case 'unit':
          await (h.db.update(h.db.products)
                ..where((t) => t.id.equals(QuotationHarness.measuredProductId)))
              .write(
                const ProductsCompanion(
                  saleUnitId: Value(InventoryUnitIds.gram),
                ),
              );
        case 'factor':
          await (h.db.update(h.db.units)
                ..where((t) => t.unitId.equals(InventoryUnitIds.kilogram)))
              .write(const UnitsCompanion(atomicFactor: Value(100)));
        case 'dimension':
          await (h.db.update(h.db.units)
                ..where((t) => t.unitId.equals(InventoryUnitIds.kilogram)))
              .write(const UnitsCompanion(dimension: Value('volume')));
        case 'reference':
          await (h.db.update(h.db.products)
                ..where((t) => t.id.equals(QuotationHarness.measuredProductId)))
              .write(
                const ProductsCompanion(
                  priceReferenceQuantityAtomic: Value(500),
                ),
              );
        case 'symbol':
          await (h.db.update(h.db.units)
                ..where((t) => t.unitId.equals(InventoryUnitIds.kilogram)))
              .write(const UnitsCompanion(symbol: Value('nuevo')));
        case 'code':
          await (h.db.update(h.db.units)
                ..where((t) => t.unitId.equals(InventoryUnitIds.kilogram)))
              .write(const UnitsCompanion(code: Value('nuevo')));
        case 'unitInactive':
          await (h.db.update(h.db.units)
                ..where((t) => t.unitId.equals(InventoryUnitIds.kilogram)))
              .write(const UnitsCompanion(active: Value(false)));
        case 'unitMissing':
          await (h.db.delete(
            h.db.units,
          )..where((t) => t.unitId.equals(InventoryUnitIds.kilogram))).go();
        case 'variantInactive':
          await (h.db.update(h.db.productVariants)
                ..where((t) => t.id.equals(QuotationHarness.recipeId)))
              .write(const ProductVariantsCompanion(active: Value(false)));
        case 'variantMissing':
          await (h.db.delete(
            h.db.productVariants,
          )..where((t) => t.id.equals(QuotationHarness.recipeId))).go();
        case 'productInactive':
          await (h.db.update(h.db.products)
                ..where((t) => t.id.equals(QuotationHarness.measuredProductId)))
              .write(const ProductsCompanion(active: Value(false)));
        case 'productMissing':
          await (h.db.delete(h.db.products)
                ..where((t) => t.id.equals(QuotationHarness.measuredProductId)))
              .go();
      }
      final before = await h.contents();
      await expectLater(
        h.service().recuperar(c),
        throwsA(
          isA<QuotationRecoveryLineException>().having(
            (e) => e.quotationItemId,
            'line',
            isNotEmpty,
          ),
        ),
      );
      expect(await h.contents(), before);
      expect((await h.repository.findById(c.quotationId))!.items.length, 3);
      expect(
        (await h.repository.findById(c.quotationId))!.status,
        QuotationStatus.disponible,
      );
    });
  }

  test(
    'Propietario, revisión, inactividad y contexto inválido se validan sin escribir',
    () async {
      final c = await available();
      final before = await h.contents();
      await expectLater(
        h.service().recuperar(copy(c, revision: 'obsolete')),
        throwsStateError,
      );
      await expectLater(
        h.service().recuperar(copy(c, quotationId: 'absent')),
        throwsStateError,
      );
      for (final owner in [
        const LocalCommandContext(
          userId: 'other',
          deviceId: 'quotation-tablet',
        ),
        const LocalCommandContext(userId: 'quotation-user', deviceId: 'other'),
      ]) {
        await expectLater(
          h.service(owner: owner).recuperar(c),
          throwsStateError,
        );
      }
      await expectLater(
        h.service().recuperar(copy(c, saleId: c.quotationId)),
        throwsFormatException,
      );
      expect(await h.contents(), before);
      await h.db
          .update(h.db.quotations)
          .write(const QuotationsCompanion(active: Value(false)));
      final inactive = await h.contents();
      await expectLater(h.service().recuperar(c), throwsStateError);
      expect(await h.contents(), inactive);
    },
  );

  for (final failure in ['secondLine', 'link', 'afterHandler']) {
    test('C25: rollback de filas, evento, refs y vínculo: $failure', () async {
      h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
      final c = await available(all: true);
      if (failure == 'secondLine') {
        await h.db.customStatement(
          "CREATE TRIGGER fail_recovery BEFORE INSERT ON sale_items WHEN NEW.sort_order = 1 BEGIN SELECT RAISE(ABORT, 'second line'); END",
        );
      } else if (failure == 'link') {
        await h.db.customStatement(
          "CREATE TRIGGER fail_recovery BEFORE UPDATE OF current_sale_id ON quotations BEGIN SELECT RAISE(ABORT, 'link'); END",
        );
      } else {
        h.failAfterRecovery = true;
      }
      final before = await h.contents();
      await expectLater(
        h.service().recuperar(c),
        throwsA(anyOf(isA<Exception>(), isA<StateError>())),
      );
      expect(await h.contents(), before);
      h.failAfterRecovery = false;
      if (failure != 'afterHandler') {
        await h.db.customStatement('DROP TRIGGER fail_recovery');
      }
      expect((await h.service().recuperar(c)).saleId, c.saleId);
    });
  }

  test(
    'C22/C27: historia no resucita ni restaura vínculos anteriores',
    () async {
      final c = await available(all: true);
      await h.service().recuperar(c);
      final old = (await h.db.quotationDao.findEventById(c.eventId))!;
      final saved = (await h.db.quotationDao.findEventById(
        c.expectedQuotationEventId,
      ))!;
      await clear(c.saleId);
      expect(
        (await h.repository.findById(c.quotationId))!.status,
        QuotationStatus.disponible,
      );
      final cleared = await h.contents();
      await h.recoveryHandler.apply(old);
      await h.handler.apply(saved);
      final retry = await h.service().recuperar(copy(c));
      expect(retry.saleId, c.saleId);
      expect(retry.draftAvailable, isFalse);
      expect(await h.contents(), cleared);
      final c2 = await next(c.quotationId);
      await h.service().recuperar(c2);
      expect(c2.saleId, isNot(c.saleId));
      expect((await h.db.saleDao.findById(c2.saleId))!.version, 3);
      expect((await h.db.quotationDao.findById(c.quotationId))!.version, 3);
      final recovered = await h.contents();
      await h.recoveryHandler.apply(old);
      await h.handler.apply(saved);
      expect(await h.contents(), recovered);
      expect((await h.service().recuperar(c)).draftAvailable, isFalse);
      await h.confirm();
      final sold = await h.contents();
      await h.recoveryHandler.apply(old);
      await h.recoveryHandler.apply(
        (await h.db.quotationDao.findEventById(c2.eventId))!,
      );
      expect(await h.contents(), sold);
    },
  );

  test(
    'C27: wasCleared protege incluso con proyección de quotation atrasada',
    () async {
      final c = await available();
      await h.service().recuperar(c);
      final e = (await h.db.quotationDao.findEventById(c.eventId))!;
      final p = CotizacionRecuperadaPayload.fromJson(e.payload);
      await clear(c.saleId);
      await h.db
          .update(h.db.quotations)
          .write(
            QuotationsCompanion(
              version: const Value(1),
              lastEventId: Value(c.expectedQuotationEventId),
              currentSaleId: Value(p.previousSaleId),
            ),
          );
      final before = await h.contents();
      await h.recoveryHandler.apply(e);
      expect(await h.contents(), before);
      await expectLater(
        h.service().recuperar(
          copy(c, eventId: '00000000-0000-4000-8000-000000000091'),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'C14/C27: colisiones de intención y contenido, IDs nunca reutilizados',
    () async {
      final c = await available();
      await h.service().recuperar(c);
      final event = (await h.db.quotationDao.findEventById(c.eventId))!;
      final before = await h.contents();
      await expectLater(
        h.service().recuperar(
          copy(c, saleId: '00000000-0000-4000-8000-000000000091'),
        ),
        throwsStateError,
      );
      await expectLater(
        h.service().recuperar(
          copy(c, time: c.recoveredAtLocal.add(const Duration(seconds: 1))),
        ),
        throwsStateError,
      );
      await expectLater(
        h.recoveryHandler.apply(
          event.copyWith(
            payload: {...event.payload, 'previous_sale_id': 'other'},
          ),
        ),
        throwsStateError,
      );
      expect(await h.contents(), before);
      await clear(c.saleId);
      await expectLater(
        h.service().recuperar(
          copy(await next(c.quotationId), saleId: c.saleId),
        ),
        throwsStateError,
      );
      await expectLater(
        h.service().recuperar(
          copy(
            await next(c.quotationId),
            saleId: CotizacionRecuperadaPayload.fromJson(
              event.payload,
            ).previousSaleId!,
          ),
        ),
        throwsStateError,
      );
      // Identidad de evento de guardado no se acepta como recuperación.
      await expectLater(
        h.service().recuperar(
          copy(await next(c.quotationId), eventId: c.expectedQuotationEventId),
        ),
        throwsStateError,
      );
    },
  );

  for (final mode in AppMode.values) {
    test(
      'C28: reinicio real conserva recuperación editada y luego venta $mode',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'pos_recovery_restart_',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => temp.path,
            );
        try {
          await h.dispose();
          h = QuotationHarness(database: AppDatabase(), mode: mode);
          await h.seed();
          final c = await available(all: true);
          await h.service().recuperar(c);
          final line = (await h.db.saleDao.items(c.saleId)).first;
          await h.drafts.actualizarProducto(
            ActualizarProductoBorradorCommand(saleItemId: line.id, quantity: 4),
          );
          await h.db.customStatement(
            'CREATE TABLE recovery_restart_marker(id TEXT)',
          );
          final before = await h.contents();
          await h.dispose();
          h = QuotationHarness(database: AppDatabase(), mode: mode);
          expect(await h.contents(), before);
          expect((await h.service().recuperar(copy(c))).saleId, c.saleId);
          expect(
            (await h.repository.findById(c.quotationId))!.status,
            QuotationStatus.enVenta,
          );
          expect(await h.contents(), before);
          final confirmation = await h.confirm();
          if (mode == AppMode.serverSync) {
            await h.db.eventDao.actualizarEstadoSincronizacion(
              confirmation,
              'rejected',
            );
          }
          final sold = await h.contents();
          await h.dispose();
          h = QuotationHarness(database: AppDatabase(), mode: mode);
          expect(await h.contents(), sold);
          await expectLater(
            h.service().recuperar(await next(c.quotationId)),
            throwsStateError,
          );
          expect(
            (await h.repository.findById(c.quotationId))!.status,
            QuotationStatus.vendida,
          );
          expect(
            await h.db
                .customSelect('PRAGMA integrity_check')
                .map((r) => r.data.values.single)
                .get(),
            ['ok'],
          );
          expect(
            await h.db.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          expect(await h.contents(), sold);
          expect(
            await h.db
                .customSelect('SELECT * FROM recovery_restart_marker')
                .get(),
            isEmpty,
          );
        } finally {
          await h.dispose();
          h = QuotationHarness();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                null,
              );
          await temp.delete(recursive: true);
        }
      },
    );
  }
}
