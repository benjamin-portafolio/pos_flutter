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
    Future<String?> Function(VariantePorCodigoBarras)? quantity,
    void Function()? onSaving,
  }) => fixture.coordinator.read(
    code,
    canContinue: canContinue ?? () => true,
    selectProduct:
        select ?? (_) async => throw StateError('Selector inesperado'),
    requestQuantity:
        quantity ?? (_) async => throw StateError('Cantidad inesperada'),
    onSaving: onSaving,
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
        return '0.750';
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
          return '0.750';
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
