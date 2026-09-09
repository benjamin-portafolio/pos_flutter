import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_result.dart';

void main() {
  testWidgets('edita datos y conserva identidad y forma de venta', (
    tester,
  ) async {
    ArticuloFormResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: ArticleFormScreen(
          categorias: const [],
          unidadesVenta: _units,
          initialValue: const ArticuloFormResult(
            nombre: 'Café',
            categoriaId: null,
            saleConfiguration: UnitSaleConfiguration(),
            variantes: [
              ArticuloFormVarianteResult(
                id: 'variant-id',
                nombre: 'Grande',
                precioVenta: '10.00',
                costoEstandar: '2.00',
              ),
            ],
          ),
          onSave: (value) async => result = value,
        ),
      ),
    );
    expect(find.text('EDITAR ARTÍCULO'), findsOneWidget);
    expect(find.text('Avanzado'), findsNothing);
    expect(find.text('Sencillo'), findsNothing);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('sale_mode_selector')))
          .onTap,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('article_name_field')),
      'Café nuevo',
    );
    await tester.ensureVisible(find.byKey(const Key('article_variant_card_0')));
    await tester.tap(find.byKey(const Key('article_variant_card_0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('delete_variant_button')))
          .onPressed,
      isNotNull,
    );
    await tester.enterText(
      find.byKey(const Key('variant_name_field')),
      'Mediano',
    );
    await tester.tap(find.text('GUARDAR').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('add_article_variant_button')),
    );
    await tester.tap(find.byKey(const Key('add_article_variant_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_name_field')),
      'Nuevo',
    );
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '15',
    );
    await tester.tap(find.text('AGREGAR').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();
    expect(result!.nombre, 'Café nuevo');
    expect(result!.variantes, hasLength(2));
    expect(result!.variantes.last.nombre, 'Nuevo');
    expect(result!.variantes.last.id, isNull);
    expect(result!.variantes.first.nombre, 'Mediano');
    expect(result!.variantes.first.id, 'variant-id');
    expect(result!.saleConfiguration, const UnitSaleConfiguration());
  });

  testWidgets(
    'edición oculta la primera variante antes de guardar y advierte al borrar la última',
    (tester) async {
      ArticuloFormResult? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: ArticleFormScreen(
            categorias: const [],
            unidadesVenta: _units,
            initialValue: const ArticuloFormResult(
              nombre: 'Café',
              categoriaId: null,
              saleConfiguration: UnitSaleConfiguration(),
              variantes: [
                ArticuloFormVarianteResult(
                  id: 'first',
                  nombre: 'Grande',
                  precioVenta: '10',
                  costoEstandar: null,
                ),
                ArticuloFormVarianteResult(
                  id: 'second',
                  nombre: 'Chica',
                  precioVenta: '8',
                  costoEstandar: null,
                ),
              ],
            ),
            onSave: (value) async => saved = value,
          ),
        ),
      );
      Future<void> openFirst() async {
        await tester.ensureVisible(
          find.byKey(const Key('article_variant_card_0')),
        );
        await tester.tap(find.byKey(const Key('article_variant_card_0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('delete_variant_button')));
        await tester.pumpAndSettle();
      }

      await openFirst();
      await tester.tap(find.text('NO'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('variant_editor_screen')), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete_variant_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_variant_button')));
      await tester.pumpAndSettle();
      expect(find.text('Grande'), findsNothing);
      expect(find.text('Chica'), findsOneWidget);
      expect(saved, isNull);
      await openFirst();
      expect(
        find.text('¿Eliminar la última variante y el producto?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirm_delete_variant_button')));
      await tester.pumpAndSettle();
      expect(find.text('Chica'), findsNothing);
      expect(find.byKey(const Key('product_pending_deletion')), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.byKey(const Key('save_article_button')));
      await tester.pumpAndSettle();
      expect(saved!.eliminarProducto, isTrue);
      expect(saved!.variantes, isEmpty);
    },
  );

  testWidgets(
    'eliminar la última variante de un alta descarta el borrador sin crear producto',
    (tester) async {
      var saves = 0;
      await _pumpForm(tester, onSave: (_) async => saves++);
      await _chooseAdvanced(tester);
      await tester.tap(find.byKey(const Key('article_variant_card_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_variant_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_variant_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('article_variant_card_0')), findsNothing);
      await tester.tap(find.byKey(const Key('save_article_button')));
      await tester.pumpAndSettle();
      expect(saves, 0);
    },
  );

  testWidgets('inicia con venta por unidad', (tester) async {
    await _pumpForm(tester);

    expect(find.text('Vender por unidad'), findsOneWidget);
    expect(find.byKey(const Key('sale_unit_selector')), findsNothing);
    expect(find.text('Sencillo'), findsOneWidget);
    expect(find.text('Avanzado'), findsOneWidget);
    expect(find.byKey(const Key('article_price_field')), findsOneWidget);
    expect(find.byKey(const Key('add_article_variant_button')), findsNothing);
  });

  testWidgets('Avanzado crea la primera tarjeta y abre su editor', (
    tester,
  ) async {
    await _pumpForm(tester);
    await _chooseAdvanced(tester);

    expect(find.byKey(const Key('article_variant_card_0')), findsOneWidget);
    expect(find.text('Variante sin nombre'), findsOneWidget);
    expect(find.byKey(const Key('add_article_variant_button')), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('save_article_button')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('article_variant_card_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('variant_name_field')), findsOneWidget);
    expect(find.text('Seguimiento de existencias'), findsOneWidget);
    expect(
      find.byKey(const Key('variant_inventory_tracking_switch')),
      findsOneWidget,
    );
  });

  testWidgets('Agregar variante reutiliza el primer borrador vacío', (
    tester,
  ) async {
    ArticuloFormResult? result;
    await _pumpForm(tester, onSave: (value) async => result = value);
    await tester.enterText(find.byKey(const Key('article_name_field')), 'Café');
    await _chooseAdvanced(tester);

    await tester.tap(find.byKey(const Key('add_article_variant_button')));
    await tester.pumpAndSettle();
    expect(find.text('GUARDAR'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('variant_name_field')),
      'Grande',
    );
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('article_variant_card_0')), findsOneWidget);
    expect(find.byKey(const Key('article_variant_card_1')), findsNothing);
    expect(find.text('Grande'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();
    expect(result?.variantes, hasLength(1));
    expect(result?.variantes.single.nombre, 'Grande');
    expect(result?.variantes.single.precioVenta, '10');
  });

  testWidgets('captura seguimiento directo y existencia inicial por variante', (
    tester,
  ) async {
    ArticuloFormResult? result;
    await _pumpForm(tester, onSave: (value) async => result = value);
    await tester.enterText(
      find.byKey(const Key('article_name_field')),
      'Agua mineral',
    );
    await _chooseAdvanced(tester);
    await tester.tap(find.byKey(const Key('article_variant_card_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '25',
    );
    await tester.tap(
      find.byKey(const Key('variant_inventory_tracking_switch')),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('variant_initial_stock_field')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('variant_initial_stock_field')),
      '15',
    );
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();
    expect(find.text('15'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();

    expect(result?.variantes.single.inventoryUnitId, 'unit_piece');
    expect(result?.variantes.single.existenciaInicial, '15');
  });

  testWidgets(
    'el editor ocupa la pantalla y alinea acciones y precios como referencia',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpForm(tester);
      await _chooseAdvanced(tester);

      await tester.tap(find.byKey(const Key('article_variant_card_0')));
      await tester.pumpAndSettle();

      final screenFinder = find.byKey(const Key('variant_editor_screen'));
      expect(tester.getSize(screenFinder), const Size(360, 640));

      final closeFinder = find.byKey(const Key('close_variant_editor_button'));
      final deleteFinder = find.byKey(const Key('delete_variant_button'));
      final saveFinder = find.byKey(const Key('save_variant_button'));
      final closeRect = tester.getRect(closeFinder);
      final deleteRect = tester.getRect(deleteFinder);
      final saveRect = tester.getRect(saveFinder);
      expect(deleteRect.left, greaterThanOrEqualTo(closeRect.right));
      expect(saveRect.left, greaterThan(deleteRect.right));
      expect(deleteRect.center.dy, closeTo(saveRect.center.dy, 0.1));

      final colorScheme = Theme.of(tester.element(deleteFinder)).colorScheme;
      final deleteButton = tester.widget<FilledButton>(deleteFinder);
      final saveButton = tester.widget<FilledButton>(saveFinder);
      expect(
        deleteButton.style?.backgroundColor?.resolve(const {}),
        colorScheme.error,
      );
      expect(
        saveButton.style?.backgroundColor?.resolve(const {}),
        const Color(0xFF4CAF50),
      );

      final saleColumn = tester.getRect(
        find.byKey(const Key('variant_sale_price_column')),
      );
      final costColumn = tester.getRect(
        find.byKey(const Key('variant_standard_cost_column')),
      );
      final marginColumn = tester.getRect(
        find.byKey(const Key('variant_margin_column')),
      );
      expect(saleColumn.top, closeTo(costColumn.top, 0.1));
      expect(costColumn.top, closeTo(marginColumn.top, 0.1));
      expect(saleColumn.right, lessThan(costColumn.left));
      expect(costColumn.right, lessThan(marginColumn.left));
      expect(find.text('Precio de venta *'), findsOneWidget);
      expect(find.text('Costo estándar'), findsOneWidget);
      expect(find.text('Margen estimado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('solo precio es obligatorio; nombre y costo vacíos son null', (
    tester,
  ) async {
    ArticuloFormResult? result;
    await _pumpForm(tester, onSave: (value) async => result = value);
    await tester.enterText(find.byKey(const Key('article_name_field')), 'Café');
    await _chooseAdvanced(tester);
    await _editVariant(tester, 0, price: '10');

    expect(find.byTooltip('Sin costo estándar'), findsOneWidget);
    final icon = tester.widget<Icon>(
      find.byKey(const Key('variant_standard_cost_icon')),
    );
    expect(icon.color, Colors.grey);

    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();
    expect(result?.variantes.single.nombre, isNull);
    expect(result?.variantes.single.costoEstandar, isNull);
    expect(result?.variantes.single.precioVenta, '10');
  });

  testWidgets('costo cero activa el icono y muestra margen 100 %', (
    tester,
  ) async {
    await _pumpForm(tester);
    await _chooseAdvanced(tester);
    await tester.tap(find.byKey(const Key('article_variant_card_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('variant_standard_cost_field')),
      '0',
    );
    await tester.pump();
    expect(find.text('100 %'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Costo estándar registrado'), findsOneWidget);
    final iconFinder = find.byKey(const Key('variant_standard_cost_icon'));
    final icon = tester.widget<Icon>(iconFinder);
    final primary = Theme.of(tester.element(iconFinder)).colorScheme.primary;
    expect(icon.color, primary);
  });

  testWidgets('venta 10 y costo 2 muestran margen 80 %', (tester) async {
    await _pumpForm(tester);
    await _chooseAdvanced(tester);
    await tester.tap(find.byKey(const Key('article_variant_card_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('variant_standard_cost_field')),
      '2',
    );
    await tester.pump();
    expect(find.text('80 %'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('variant_standard_cost_field')),
      '12',
    );
    await tester.pump();
    expect(find.text('-20 %'), findsOneWidget);
  });

  testWidgets('cerrar el editor no modifica ni agrega borradores', (
    tester,
  ) async {
    await _pumpForm(tester);
    await _chooseAdvanced(tester);
    await tester.tap(find.byKey(const Key('article_variant_card_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_name_field')),
      'Temporal',
    );
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    await tester.tap(find.byKey(const Key('close_variant_editor_button')));
    await tester.pumpAndSettle();
    expect(find.text('Variante sin nombre'), findsOneWidget);
    expect(find.text('Temporal'), findsNothing);

    await tester.tap(find.byKey(const Key('add_article_variant_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '12',
    );
    await tester.tap(find.byKey(const Key('close_variant_editor_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article_variant_card_1')), findsNothing);
  });

  testWidgets('rechaza costo negativo', (tester) async {
    await _pumpForm(tester);
    await _chooseAdvanced(tester);
    await tester.tap(find.byKey(const Key('article_variant_card_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('variant_standard_cost_field')),
      '-1',
    );
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pump();
    expect(find.textContaining('no negativo'), findsOneWidget);
  });

  testWidgets(
    'agrega varias variantes y confirma el borrado de una adicional',
    (tester) async {
      await _pumpForm(tester);
      await _chooseAdvanced(tester);
      await _editVariant(tester, 0, name: 'Grande', price: '10');

      await tester.tap(find.byKey(const Key('article_variant_card_0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('delete_variant_button')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('close_variant_editor_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_article_variant_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('variant_sale_price_field')),
        '12',
      );
      await tester.tap(find.byKey(const Key('save_variant_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('article_variant_card_1')), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('article_variant_card_1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('article_variant_card_1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('delete_variant_button')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('delete_variant_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_variant_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('article_variant_card_1')), findsNothing);
      expect(find.byKey(const Key('article_variant_card_0')), findsOneWidget);
    },
  );

  testWidgets('reordena variantes y guarda la nueva posición', (tester) async {
    ArticuloFormResult? result;
    await _pumpForm(tester, onSave: (value) async => result = value);
    await tester.enterText(find.byKey(const Key('article_name_field')), 'Café');
    await _chooseAdvanced(tester);
    await _editVariant(tester, 0, name: 'Chica', price: '10');

    await tester.tap(find.byKey(const Key('add_article_variant_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_name_field')),
      'Grande',
    );
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '20',
    );
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    final firstCard = find.byKey(const Key('article_variant_card_0'));
    final secondCard = find.byKey(const Key('article_variant_card_1'));
    final firstUp = find.descendant(
      of: firstCard,
      matching: find.byKey(const Key('move_article_variant_up_button')),
    );
    final firstDown = find.descendant(
      of: firstCard,
      matching: find.byKey(const Key('move_article_variant_down_button')),
    );
    final secondDown = find.descendant(
      of: secondCard,
      matching: find.byKey(const Key('move_article_variant_down_button')),
    );

    expect(tester.widget<IconButton>(firstUp).onPressed, isNull);
    expect(tester.widget<IconButton>(secondDown).onPressed, isNull);

    await tester.tap(firstDown);
    await tester.pump();

    expect(
      find.descendant(of: firstCard, matching: find.text('Grande')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondCard, matching: find.text('Chica')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();

    expect(result?.variantes.map((variant) => variant.nombre), [
      'Grande',
      'Chica',
    ]);
  });

  testWidgets('rechaza nombres duplicados tras normalización', (tester) async {
    await _pumpForm(tester);
    await _chooseAdvanced(tester);
    await _editVariant(tester, 0, name: 'Grande', price: '10');
    await tester.tap(find.byKey(const Key('add_article_variant_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_name_field')),
      'ＧＲＡＮＤＥ',
    );
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '12',
    );
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pump();
    expect(
      find.text('Ya existe una variante con este nombre.'),
      findsOneWidget,
    );
  });

  testWidgets('impide volver a Sencillo si perdería datos avanzados', (
    tester,
  ) async {
    await _pumpForm(tester);
    await _chooseAdvanced(tester);
    await _editVariant(tester, 0, price: '10', cost: '2');
    await tester.tap(find.text('Sencillo'));
    await tester.pump();
    expect(find.byKey(const Key('article_variant_card_0')), findsOneWidget);
    expect(
      find.textContaining('no puede representar las variantes o costos'),
      findsOneWidget,
    );
  });

  testWidgets('reutiliza el precio al alternar un borrador representable', (
    tester,
  ) async {
    await _pumpForm(tester);
    await tester.enterText(find.byKey(const Key('article_price_field')), '15');
    await _chooseAdvanced(tester);
    expect(find.text(r'$15.00'), findsOneWidget);
    await tester.tap(find.text('Sencillo'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('article_price_field')))
          .controller
          ?.text,
      '15',
    );
  });

  testWidgets('conserva variantes cuando falla el commit', (tester) async {
    await _pumpForm(
      tester,
      onSave: (_) async => throw StateError('fallo simulado'),
    );
    await tester.enterText(find.byKey(const Key('article_name_field')), 'Café');
    await _chooseAdvanced(tester);
    await _editVariant(tester, 0, name: 'Grande', price: '10', cost: '2');
    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article_save_error')), findsOneWidget);
    expect(find.text('Grande'), findsOneWidget);
    expect(find.text(r'$10.00'), findsOneWidget);
    expect(find.text(r'$2.00'), findsOneWidget);
  });

  testWidgets('measured ofrece masa y volumen, usa factor y cambia precio', (
    tester,
  ) async {
    ArticuloFormResult? result;
    await _pumpForm(tester, onSave: (value) async => result = value);

    await _chooseMeasured(tester);
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
    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();
    expect(result!.saleConfiguration, const UnitSaleConfiguration());
  });

  testWidgets('no desborda a 720 px con texto ampliado y teclado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpForm(tester, textScaler: const TextScaler.linear(2));
    await _chooseAdvanced(tester);
    await tester.tap(find.byKey(const Key('article_variant_card_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _editVariant(
  WidgetTester tester,
  int index, {
  String? name,
  required String price,
  String? cost,
}) async {
  await tester.tap(find.byKey(Key('article_variant_card_$index')));
  await tester.pumpAndSettle();
  if (name != null) {
    await tester.enterText(find.byKey(const Key('variant_name_field')), name);
  }
  await tester.enterText(
    find.byKey(const Key('variant_sale_price_field')),
    price,
  );
  if (cost != null) {
    await tester.enterText(
      find.byKey(const Key('variant_standard_cost_field')),
      cost,
    );
  }
  await tester.tap(find.byKey(const Key('save_variant_button')));
  await tester.pumpAndSettle();
}

Future<void> _chooseAdvanced(WidgetTester tester) async {
  await tester.tap(find.text('Avanzado'));
  await tester.pumpAndSettle();
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
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
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
