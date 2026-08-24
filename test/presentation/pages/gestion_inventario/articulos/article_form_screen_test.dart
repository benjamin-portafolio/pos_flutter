import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_result.dart';

void main() {
  testWidgets('inicia con venta por unidad', (tester) async {
    await _pumpForm(tester);

    expect(find.text('Vender por unidad'), findsOneWidget);
    expect(find.byKey(const Key('sale_unit_selector')), findsNothing);
    expect(find.text('Sencillo'), findsOneWidget);
    expect(find.text('Avanzado'), findsOneWidget);
    expect(find.byKey(const Key('article_price_field')), findsOneWidget);
    expect(find.byKey(const Key('add_article_variant_button')), findsNothing);

    await tester.tap(find.byKey(const Key('sale_mode_selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sale_mode_unit_option')), findsOneWidget);
    expect(find.byKey(const Key('sale_mode_measured_option')), findsOneWidget);
  });

  testWidgets(
    'el alta avanzada oculta el precio y deja agregar variante pendiente',
    (tester) async {
      await _pumpForm(tester);

      await tester.tap(find.text('Avanzado'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('article_price_field')), findsNothing);
      expect(
        find.byKey(const Key('add_article_variant_button')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('add_article_variant_button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('save_article_button')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Sencillo'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('article_price_field')), findsOneWidget);
      expect(find.byKey(const Key('add_article_variant_button')), findsNothing);
    },
  );

  testWidgets('measured ofrece masa y volumen, usa factor y cambia precio', (
    tester,
  ) async {
    ArticuloFormResult? result;
    await _pumpForm(tester, onSave: (value) async => result = value);

    await _chooseMeasured(tester);
    expect(find.text('Vender por fracción'), findsOneWidget);
    expect(find.byKey(const Key('sale_unit_selector')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sale_unit_selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sale_unit_option_kg')), findsOneWidget);
    expect(find.byKey(const Key('sale_unit_option_l')), findsOneWidget);
    expect(find.byKey(const Key('sale_unit_option_piece')), findsNothing);
    expect(find.byKey(const Key('sale_unit_option_g')), findsNothing);

    await tester.tap(find.byKey(const Key('sale_unit_option_kg')));
    await tester.pumpAndSettle();
    expect(find.text('Precio de venta por 1 kg *'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('article_name_field')),
      'Queso',
    );
    await tester.enterText(find.byKey(const Key('article_price_field')), '180');
    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();

    final measured = result!.saleConfiguration as MeasuredSaleConfiguration;
    expect(measured.saleUnitId, 'unit_kg');
    expect(measured.priceReferenceQuantityAtomic, 1000);
  });

  testWidgets('no guarda measured sin unidad y volver a unit la limpia', (
    tester,
  ) async {
    ArticuloFormResult? result;
    await _pumpForm(tester, onSave: (value) async => result = value);
    await tester.enterText(
      find.byKey(const Key('article_name_field')),
      'Queso',
    );
    await tester.enterText(find.byKey(const Key('article_price_field')), '180');
    await _chooseMeasured(tester);

    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sale_unit_error')), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.byKey(const Key('sale_unit_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sale_unit_option_kg')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sale_mode_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sale_mode_unit_option')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sale_unit_selector')), findsNothing);
    expect(find.text('Precio de venta *'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();
    expect(result!.saleConfiguration, const UnitSaleConfiguration());
  });

  testWidgets('cambiar un selector activa la advertencia de cambios', (
    tester,
  ) async {
    await _pumpForm(tester);
    await _chooseMeasured(tester);
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Descartar cambios'), findsOneWidget);
  });
}

Future<void> _chooseMeasured(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sale_mode_selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('sale_mode_measured_option')));
  await tester.pumpAndSettle();
}

Future<void> _pumpForm(
  WidgetTester tester, {
  Future<void> Function(ArticuloFormResult result)? onSave,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ArticleFormScreen(
        categorias: const [],
        unidadesVenta: _units,
        onSave: onSave ?? (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _units = [
  UnidadInventario(
    id: 'unit_piece',
    code: 'piece',
    nombre: 'Pieza',
    simbolo: 'pza',
    dimension: DimensionUnidad.count,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  ),
  UnidadInventario(
    id: 'unit_kg',
    code: 'kg',
    nombre: 'Kilogramo',
    simbolo: 'kg',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  ),
  UnidadInventario(
    id: 'unit_g',
    code: 'g',
    nombre: 'Gramo',
    simbolo: 'g',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: false,
  ),
  UnidadInventario(
    id: 'unit_l',
    code: 'l',
    nombre: 'Litro',
    simbolo: 'L',
    dimension: DimensionUnidad.volume,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  ),
];
