import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/sale_item_snapshot.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/ventas/measured_sale_conditions.dart';
import 'package:pos_flutter/domain/ventas/sale_draft.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/articulos/measured_sale_preview.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_dialog.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_form_result.dart';

const amountKey = ValueKey('sale-target-amount');
const quantityKey = ValueKey('sale-measured-quantity');

MeasuredSaleConditions conditions({
  int price = 6000,
  int reference = 1000,
  String code = 'kg',
}) => MeasuredSaleConditions(
  variantId: 'variant',
  productName: 'Granel',
  variantName: 'Original',
  unit: UnidadInventario(
    id: code,
    code: code,
    nombre: code,
    simbolo: code,
    dimension: ['kg', 'g'].contains(code)
        ? DimensionUnidad.mass
        : DimensionUnidad.volume,
    factorAtomico: ['kg', 'L'].contains(code) ? 1000 : 1,
    maximosDecimales: ['kg', 'L'].contains(code) ? 3 : 0,
    activa: true,
  ),
  unitPriceMinor: price,
  priceReferenceQuantityAtomic: reference,
  standardCostMinor: 20,
  consumptionConfigurationKey: 'consumption',
);

SaleDraft draftWith(SaleItemSnapshot item) => SaleDraft(
  id: 'sale',
  lastEventId: 'event',
  totalMinor: item.totalMinor,
  items: [
    SaleDraftItem(
      id: 'line',
      variantId: item.variantId,
      productName: item.productName,
      variantName: item.variantName,
      quantity: item.quantity,
      measuredQuantityAtomic: item.measuredQuantityAtomic,
      unitPriceMinor: item.unitPriceMinor,
      standardCostMinor: item.standardCostMinor,
      consumptionConfigurationKey: item.consumptionConfigurationKey,
      priceReferenceQuantityAtomic: item.priceReferenceQuantityAtomic,
      unitCode: item.unitCode,
      unitSymbol: item.unitSymbol,
      unitAtomicFactor: item.unitAtomicFactor,
      totalMinor: item.totalMinor,
    ),
  ],
);

void main() {
  late List<SaleQuantityFormResult?> results;

  Future<void> open(
    WidgetTester tester, {
    MeasuredSaleConditions? catalog,
    Stream<SaleDraft?>? drafts,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    results = [];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await showDialog<SaleQuantityFormResult>(
                    context: context,
                    builder: (_) => SaleQuantityDialog(
                      loadConditions: () async => catalog ?? conditions(),
                      draft: drafts ?? Stream.value(null),
                    ),
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;
  String quantity(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(quantityKey)).controller!.text;
  String amount(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(amountKey)).controller!.text;

  testWidgets(
    'pesos vacíos con foco; ceil, cobro y ajuste visibles; Enter conserva intención',
    (tester) async {
      await open(tester);
      expect(amount(tester), isEmpty);
      expect(enabled(tester), isFalse);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(amountKey),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(
        tester.getTopLeft(find.byKey(amountKey)).dy,
        lessThan(tester.getTopLeft(find.byKey(quantityKey)).dy),
      );
      await tester.enterText(find.byKey(amountKey), '20');
      await tester.pump();
      expect(quantity(tester), '0.334');
      expect(amount(tester), '20');
      expect(find.text(r'Cobro por esta cantidad: $20.04'), findsOneWidget);
      expect(find.text(r'Ajuste por peso: +$0.04'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final result = results.single!;
      expect(result.targetAmountMinor, 2000);
      expect(result.measuredQuantity, isNull);
      expect(result.expectedUnitId, 'kg');
      expect(result.expectedUnitPriceMinor, 6000);
      expect(result.expectedPriceReferenceQuantityAtomic, 1000);
      expect(result.toCommand('variant').targetAmountMinor, 2000);
    },
  );

  for (final data in [
    (8000, 1000, 'kg', '20', '0.25', r'$20.00'),
    (1200, 100, 'g', '20', '167', r'$20.04'),
    (4000, 1000, 'L', '15', '0.375', r'$15.00'),
    (4000, 1000, 'ml', '15', '375', r'$15.00'),
    (6000, 1000, 'kg', '0.01', '0.001', r'$0.06'),
  ]) {
    testWidgets('importe ${data.$4} a ${data.$1}/${data.$2} ${data.$3}', (
      tester,
    ) async {
      await open(
        tester,
        catalog: conditions(price: data.$1, reference: data.$2, code: data.$3),
      );
      await tester.enterText(find.byKey(amountKey), data.$4);
      await tester.pump();
      expect(quantity(tester), data.$5);
      expect(find.text('Cobro por esta cantidad: ${data.$6}'), findsOneWidget);
      expect(enabled(tester), isTrue);
    });
  }

  testWidgets('alternar campos conserva fuente y foco; cantidad manual 333 g', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byKey(amountKey), ' 20,00 ');
    await tester.pump();
    expect(amount(tester), ' 20,00 ');
    expect(quantity(tester), '0.334');
    await tester.enterText(find.byKey(quantityKey), '0,333');
    await tester.pump();
    expect(amount(tester), '19.98');
    expect(find.text(r'Cobro por esta cantidad: $19.98'), findsOneWidget);
    expect(find.textContaining('Ajuste por peso'), findsNothing);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(quantityKey),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();
    expect(results.single!.measuredQuantity, '0,333');
    expect(results.single!.targetAmountMinor, isNull);
  });

  for (final invalid in [
    '',
    '20.',
    '20,',
    '.',
    '-1',
    '0',
    '1.234',
    '1,000.00',
    '1 000',
    'abc',
    '90071992547409.92',
  ]) {
    testWidgets(
      'importe inválido/temporal "$invalid" descarta cantidad anterior',
      (tester) async {
        await open(tester);
        await tester.enterText(find.byKey(amountKey), '20');
        await tester.pump();
        expect(enabled(tester), isTrue);
        await tester.enterText(find.byKey(amountKey), invalid);
        await tester.pump();
        expect(quantity(tester), isEmpty);
        expect(enabled(tester), isFalse);
        expect(find.textContaining('Cobro por esta cantidad'), findsNothing);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(results, isEmpty);
      },
    );
  }

  testWidgets(
    'cantidad inválida borra importe previo; peso de total cero sigue válido',
    (tester) async {
      await open(
        tester,
        catalog: conditions(price: 1, reference: 3, code: 'g'),
      );
      await tester.enterText(find.byKey(amountKey), '0.01');
      await tester.pump();
      await tester.enterText(find.byKey(quantityKey), '1.');
      await tester.pump();
      expect(amount(tester), isEmpty);
      expect(enabled(tester), isFalse);
      await tester.enterText(find.byKey(quantityKey), '1');
      await tester.pump();
      expect(amount(tester), '0.00');
      expect(enabled(tester), isTrue);
      expect(find.text(r'Cobro por esta cantidad: $0.00'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(results.single!.targetAmountMinor, isNull);
      expect(results.single!.measuredQuantity, '1');
    },
  );

  testWidgets('Enter de una vista anterior espera el nuevo cobro visible', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byKey(amountKey), '20');
    await tester.pump();
    final previousEnter = tester
        .widget<TextField>(find.byKey(amountKey))
        .onSubmitted!;
    final previousButton = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    await tester.enterText(find.byKey(amountKey), '30');
    previousEnter('30');
    previousButton();
    expect(results, isEmpty);
    await tester.pump();
    expect(find.text(r'Cobro por esta cantidad: $30.00'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(results.single!.targetAmountMinor, 3000);
  });

  testWidgets(
    'cancelar no entrega intención; doble pulsación entrega solo una',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(amountKey), '20');
      await tester.pump();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(results, [null]);
      await open(tester);
      await tester.enterText(find.byKey(amountKey), '20');
      await tester.pump();
      final submit = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      submit();
      submit();
      await tester.pumpAndSettle();
      expect(results, hasLength(1));
      expect(results.single!.targetAmountMinor, 2000);
    },
  );

  testWidgets(
    'observa borrador; acumulación completa 668 g / 40.08 y limpieza',
    (tester) async {
      final updates = StreamController<SaleDraft?>();
      addTearDown(updates.close);
      await open(tester, drafts: updates.stream);
      updates.add(null);
      await tester.pump();
      await tester.enterText(find.byKey(amountKey), '20');
      await tester.pump();
      updates.add(
        draftWith(const MeasuredSalePreview().capture(conditions(), 334)),
      );
      await tester.pump();
      expect(
        find.text(r'Línea acumulada prevista: 0.668 kg · $40.08'),
        findsOneWidget,
      );
      updates.add(null);
      await tester.pump();
      expect(find.textContaining('Línea acumulada prevista'), findsNothing);
    },
  );

  testWidgets('fracciones de centavo redondean sobre toda la línea', (
    tester,
  ) async {
    final catalog = conditions(price: 1, reference: 3, code: 'g');
    await open(
      tester,
      catalog: catalog,
      drafts: Stream.value(
        draftWith(const MeasuredSalePreview().capture(catalog, 1)),
      ),
    );
    await tester.enterText(find.byKey(amountKey), '0.01');
    await tester.pump();
    expect(find.text(r'Cobro por esta cantidad: $0.01'), findsOneWidget);
    expect(find.text(r'Línea acumulada prevista: 4 g · $0.01'), findsOneWidget);
  });

  for (final change in <String, Object?>{
    'variant_id': 'other',
    'consumption_configuration_key': null,
    'product_name_snapshot': 'Otro',
    'variant_name_snapshot': null,
    'unit_price_minor': 6001,
    'standard_cost_minor_snapshot': null,
    'price_reference_quantity_atomic_snapshot': 100,
    'sale_unit_code_snapshot': 'g',
    'sale_unit_symbol_snapshot': 'otro',
    'sale_unit_atomic_factor_snapshot': 1,
  }.entries) {
    test('no agrupa si cambia ${change.key}', () {
      const preview = MeasuredSalePreview();
      final capture = preview.capture(conditions(), 334);
      final different = SaleItemSnapshot.fromJson({
        ...capture.toJson(),
        change.key: change.value,
      });
      expect(preview.accumulated(capture, draftWith(different)), isNull);
    });
  }

  testWidgets(
    'límite monetario válido; acumulación fuera de rango bloquea aceptar',
    (tester) async {
      final catalog = conditions(price: 1, reference: 1, code: 'g');
      await open(tester, catalog: catalog);
      await tester.enterText(find.byKey(amountKey), '90071992547409.91');
      await tester.pump();
      expect(quantity(tester), '9007199254740991');
      expect(enabled(tester), isTrue);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      final existing = const MeasuredSalePreview().capture(
        catalog,
        9007199254740991,
      );
      await open(
        tester,
        catalog: catalog,
        drafts: Stream.value(draftWith(existing)),
      );
      await tester.enterText(find.byKey(amountKey), '0.01');
      await tester.pump();
      expect(enabled(tester), isFalse);
      expect(find.textContaining('rango permitido'), findsOneWidget);
    },
  );

  testWidgets(
    'fracción de gramo y cantidad fuera de rango borran la intención previa',
    (tester) async {
      await open(tester, catalog: conditions(code: 'g'));
      for (final text in ['1.1', '9007199254740992', '']) {
        await tester.enterText(find.byKey(amountKey), '20');
        await tester.pump();
        expect(enabled(tester), isTrue);
        await tester.enterText(find.byKey(quantityKey), text);
        await tester.pump();
        expect(enabled(tester), isFalse);
        expect(amount(tester), isEmpty);
      }
    },
  );

  test('una línea por piezas nunca se combina con una captura medida', () {
    const preview = MeasuredSalePreview();
    final capture = preview.capture(conditions(), 334);
    final pieces = SaleItemSnapshot(
      variantId: capture.variantId,
      productName: capture.productName,
      variantName: capture.variantName,
      saleMode: 'unit',
      quantity: 1,
      measuredQuantityAtomic: null,
      unitPriceMinor: capture.unitPriceMinor,
      standardCostMinor: capture.standardCostMinor,
      consumptionConfigurationKey: capture.consumptionConfigurationKey,
      priceReferenceQuantityAtomic: null,
      unitCode: null,
      unitSymbol: null,
      unitAtomicFactor: null,
    );
    expect(preview.accumulated(capture, draftWith(pieces)), isNull);
  });

  testWidgets(
    'teclado, ventana pequeña y texto ampliado permiten revisar y aceptar',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await open(tester, textScaler: TextScaler.linear(2));
      await tester.enterText(find.byKey(amountKey), '20');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(r'Cobro por esta cantidad: $20.04'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      expect(results.single!.targetAmountMinor, 2000);
    },
  );
}
