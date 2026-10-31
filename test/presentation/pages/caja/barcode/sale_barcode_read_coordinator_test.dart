import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/ventas/cambiar_tarifa_venta_borrador_command.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_form_result.dart';
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/variante_por_codigo_barras.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/sale_barcode_read_outcome.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/sale_barcode_assigned_exception.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/sale_barcode_read_result.dart';

import '../../../../support/barcode_sale_fixture.dart';

void main() {
  late BarcodeSaleFixture fixture;
  setUp(() async {
    fixture = BarcodeSaleFixture();
    await fixture.seed();
  });
  tearDown(() => fixture.dispose());

  Future<SaleBarcodeReadResult> read(
    String code, {
    bool Function()? canContinue,
    Future<VariantePorCodigoBarras?> Function(List<VariantePorCodigoBarras>)?
    select,
    Future<SaleQuantityFormResult?> Function(VariantePorCodigoBarras)? quantity,
    void Function()? onSaving,
    Future<VariantePorCodigoBarras?> Function(String)? assign,
  }) => fixture.coordinator.read(
    code,
    canContinue: canContinue ?? () => true,
    selectProduct:
        select ?? (_) async => throw StateError('Selector inesperado'),
    requestQuantity:
        quantity ?? (_) async => throw StateError('Cantidad inesperada'),
    onSaving: onSaving,
    assignUnknownCode: assign,
  );

  test(
    'S4 lector comparte precio efectivo de piezas e importe medido',
    () async {
      await (fixture.db.update(fixture.db.productVariants)
            ..where((t) => t.id.equals('A')))
          .write(const ProductVariantsCompanion(offerPriceMinor: Value(80)));
      await (fixture.db.update(fixture.db.productVariants)
            ..where((t) => t.id.equals('M')))
          .write(const ProductVariantsCompanion(offerPriceMinor: Value(10000)));
      await fixture.commands.cambiarTarifa(
        CambiarTarifaVentaBorradorCommand(
          operationId: const Uuid().v4(),
          saleId: const Uuid().v4(),
          pricingMode: 'offer',
          expectedVersion: 0,
          expectedDraftEventId: null,
          expectedTotalMinor: 0,
        ),
      );
      await read('001');
      final conditions = (await fixture.coordinator.conditionsFor('M'))!;
      expect(conditions.unitPriceMinor, 10000);
      await read(
        '004',
        quantity: (_) async => SaleQuantityFormResult(
          measuredQuantity: null,
          targetAmountMinor: 1000,
          expectedUnitId: conditions.unit.id,
          expectedUnitPriceMinor: conditions.unitPriceMinor,
          expectedPriceReferenceQuantityAtomic:
              conditions.priceReferenceQuantityAtomic,
          displayQuantity: '0.1',
          displayUnitSymbol: 'kg',
        ),
      );
      expect((await fixture.draft)!.totalMinor, 1080);
      expect((await fixture.draft)!.items.last.measuredQuantityAtomic, 100);
    },
  );
  test(
    'S4 cambio durante diálogo rechaza antes de guardar en la venta',
    () async {
      await read('001');
      final before = (await fixture.draft)!;
      await expectLater(
        read(
          '004',
          quantity: (_) async {
            final s = (await fixture.db.saleDao.findById(before.id))!;
            await fixture.commands.cambiarTarifa(
              CambiarTarifaVentaBorradorCommand(
                operationId: const Uuid().v4(),
                saleId: s.id,
                pricingMode: 'offer',
                expectedVersion: s.version,
                expectedDraftEventId: s.lastEventId,
                expectedTotalMinor: s.totalMinor,
              ),
            );
            return measuredBarcodeResult('0.1');
          },
        ),
        throwsStateError,
      );
      expect((await fixture.draft)!.items, hasLength(1));
      expect((await fixture.draft)!.totalMinor, 100);
    },
  );

  for (final mode in AppMode.values) {
    test('pieza, contrato e idempotencia reales en ${mode.name}', () async {
      fixture.config.update(AppConfig.initial.copyWith(mode: mode));
      final result = await read('001');
      expect(result.outcome, SaleBarcodeReadOutcome.added);
      expect(result.candidate!.varianteId, 'A');
      expect(result.measuredQuantity, isNull);
      expect(fixture.attempts.single.expectedUnitId, isNull);
      final sale = (await fixture.draft)!;
      expect(sale.items.single.quantity, 1);
      expect(sale.totalMinor, 100);
      final events = await fixture.db.select(fixture.db.events).get();
      expect(events, hasLength(1));
      expect(events.single.deliveryStatus, 'not_required');
      expect(await fixture.db.eventDao.obtenerEventosPendientes(), isEmpty);
      expect(
        await fixture.db.select(fixture.db.eventRefs).get(),
        hasLength(mode == AppMode.standalone ? 0 : 4),
      );
      final stored = events.single;
      await fixture.processor.apply(
        SyncEvent(
          eventId: stored.eventId,
          aggregateType: stored.aggregateType,
          aggregateId: stored.aggregateId,
          eventType: stored.eventType,
          deviceId: stored.deviceId,
          userId: stored.userId,
          createdAtLocal: stored.createdAtLocal,
          deliveryStatus: stored.deliveryStatus,
          baseVersion: stored.baseVersion,
          payload: (jsonDecode(stored.payload) as Map).cast<String, Object?>(),
        ),
      );
      expect((await fixture.draft)!.items.single.quantity, 1);
    });
  }

  test('desconocido informa sin selección ni escritura', () async {
    expect((await read('999')).outcome, SaleBarcodeReadOutcome.notFound);
    expect(fixture.attempts, isEmpty);
    await fixture.expectNoWrites();
  });

  test('cancelar asignación no agrega ni escribe', () async {
    final result = await read('999', assign: (_) async => null);
    expect(result.outcome, SaleBarcodeReadOutcome.selectionCancelled);
    expect(result.barcodeAssigned, isFalse);
    await fixture.expectNoWrites();
  });

  test('respuesta tardía de asignación no agrega en otra sesión', () async {
    final answer = Completer<VariantePorCodigoBarras?>();
    var current = true;
    final operation = read(
      '999',
      canContinue: () => current,
      assign: (_) => answer.future,
    );
    final candidate = (await fixture.products.buscarVariantesPorCodigoBarras(
      '001',
    )).single;
    current = false;
    answer.complete(candidate);
    expect((await operation).outcome, SaleBarcodeReadOutcome.interrupted);
    await fixture.expectNoWrites();
  });

  for (final committed in [false, true]) {
    test(
      'fallo de venta tras asignar informa guardado, commit=$committed',
      () async {
        Future<void> fail(_) async =>
            throw StateError('respuesta de venta fallida');
        if (committed) {
          fixture.afterSave = fail;
        } else {
          fixture.beforeSave = fail;
        }
        await expectLater(
          read(
            '999',
            assign: (_) async =>
                (await fixture.products.buscarVariantesPorCodigoBarras(
                  '001',
                )).single,
          ),
          throwsA(isA<SaleBarcodeAssignedException>()),
        );
        expect(fixture.attempts, hasLength(1));
        expect(await fixture.draft, committed ? isNotNull : isNull);
      },
    );
  }

  test(
    'cantidad cancelada tras asignar conserva aviso de código guardado',
    () async {
      final result = await read(
        '999',
        assign: (_) async =>
            (await fixture.products.buscarVariantesPorCodigoBarras(
              '004',
            )).single,
        quantity: (_) async => null,
      );
      expect(result.barcodeAssigned, isTrue);
      expect(result.outcome, SaleBarcodeReadOutcome.quantityCancelled);
      await fixture.expectNoWrites();
    },
  );

  test('consulta omite producto o variante inactivos', () async {
    await (fixture.db.update(fixture.db.products)
          ..where((row) => row.id.equals('product-A')))
        .write(const ProductsCompanion(active: Value(false)));
    await (fixture.db.update(fixture.db.productVariants)
          ..where((row) => row.id.equals('B')))
        .write(const ProductVariantsCompanion(active: Value(false)));
    expect((await read('001')).outcome, SaleBarcodeReadOutcome.notFound);
    expect((await read('002')).outcome, SaleBarcodeReadOutcome.notFound);
    await fixture.expectNoWrites();
  });

  test('varias coincidencias agregan exclusivamente la seleccionada', () async {
    final result = await read(
      '003',
      select: (candidates) async {
        expect(candidates.map((c) => c.varianteId), ['C', 'D']);
        return candidates.last;
      },
    );
    expect(result.outcome, SaleBarcodeReadOutcome.added);
    expect(fixture.attempts.single.variantId, 'D');
    expect((await fixture.draft)!.items.single.variantId, 'D');
  });

  test('cancelar selector no genera comando ni evento', () async {
    final result = await read('003', select: (_) async => null);
    expect(result.outcome, SaleBarcodeReadOutcome.selectionCancelled);
    expect(fixture.attempts, isEmpty);
    await fixture.expectNoWrites();
  });

  test('cantidad medida conserva texto y expectedUnitId', () async {
    final result = await read(
      '004',
      quantity: (candidate) async {
        expect(candidate.unidadVenta!.simbolo, 'kg');
        return measuredBarcodeResult('0.750');
      },
    );
    expect(result.outcome, SaleBarcodeReadOutcome.added);
    expect(result.measuredQuantity, '0.750');
    expect(fixture.attempts.single.measuredQuantity, '0.750');
    expect(fixture.attempts.single.expectedUnitId, InventoryUnitIds.kilogram);
    expect((await fixture.draft)!.items.single.measuredQuantityAtomic, 750);
    expect((await fixture.draft)!.totalMinor, 15000);
  });

  test('cancelar cantidad no genera comando ni evento', () async {
    final result = await read('004', quantity: (_) async => null);
    expect(result.outcome, SaleBarcodeReadOutcome.quantityCancelled);
    expect(fixture.attempts, isEmpty);
    await fixture.expectNoWrites();
  });

  test('unidad inactiva impide solicitar cantidad', () async {
    await (fixture.db.update(fixture.db.units)
          ..where((row) => row.unitId.equals(InventoryUnitIds.kilogram)))
        .write(const UnitsCompanion(active: Value(false)));
    expect((await read('004')).outcome, SaleBarcodeReadOutcome.unitUnavailable);
    await fixture.expectNoWrites();
  });

  test('cambio de unidad en diálogo lo rechaza el comando real', () async {
    await expectLater(
      read(
        '004',
        quantity: (_) async {
          await (fixture.db.update(
            fixture.db.products,
          )..where((row) => row.id.equals('product-M'))).write(
            const ProductsCompanion(saleUnitId: Value(InventoryUnitIds.gram)),
          );
          return measuredBarcodeResult('0.750');
        },
      ),
      throwsStateError,
    );
    expect(fixture.attempts.single.expectedUnitId, InventoryUnitIds.kilogram);
    await fixture.expectNoWrites();
  });

  for (final code in ['001', '003', '004']) {
    test('consulta obsoleta de $code no abre diálogos ni guarda', () async {
      final gate = Completer<void>();
      var current = true;
      fixture.beforeLookup = (_) => gate.future;
      final operation = read(code, canContinue: () => current);
      current = false;
      gate.complete();
      expect((await operation).outcome, SaleBarcodeReadOutcome.interrupted);
      expect(fixture.attempts, isEmpty);
      await fixture.expectNoWrites();
    });
  }

  test('finalizar desde el aviso de guardado impide iniciar comando', () async {
    var current = true;
    final result = await read(
      '001',
      canContinue: () => current,
      onSaving: () => current = false,
    );
    expect(result.outcome, SaleBarcodeReadOutcome.interrupted);
    expect(fixture.attempts, isEmpty);
    await fixture.expectNoWrites();
  });

  test('solo confirma agregado después de finalizar el comando', () async {
    final gate = Completer<void>();
    fixture.beforeSave = (_) => gate.future;
    var completed = false;
    final operation = read('001').then((result) {
      completed = true;
      return result;
    });
    await fixture.waitFor(() => fixture.attempts.isNotEmpty);
    expect(completed, isFalse);
    await fixture.expectNoWrites();
    gate.complete();
    expect((await operation).outcome, SaleBarcodeReadOutcome.added);
    expect((await fixture.draft)!.items.single.quantity, 1);
  });
}
