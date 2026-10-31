import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_result.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_command.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/capturar_oferta_masiva.dart';

void main() {
  for (final action in ['conservar', 'establecer', 'retirar']) {
    testWidgets(
      'editor individual $action oferta y conserva costo/comando/copia',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ArticuloFormVarianteResult? result;
        await tester.pumpWidget(
          MaterialApp(
            home: VariantEditorScreen(
              initialValue: const ArticuloFormVarianteResult(
                nombre: null,
                precioVenta: '20',
                costoEstandar: '3',
                offerPriceMinor: 1500,
              ),
              canDelete: false,
              existingNameKeys: const {},
              inventoryUnit: const UnidadInventario(
                id: 'piece',
                code: 'piece',
                nombre: 'Pieza',
                simbolo: 'pza',
                dimension: DimensionUnidad.count,
                factorAtomico: 1,
                maximosDecimales: 0,
                activa: true,
              ),
              onSave: (v) async {
                result = v;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('variant_offer_price_field'));
        expect(tester.widget<TextFormField>(field).controller!.text, '15.00');
        if (action != 'conservar') {
          await tester.enterText(field, action == 'retirar' ? '' : '12.34');
        }
        await tester.tap(find.byKey(const Key('save_variant_button')));
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        expect(result!.costoEstandar, '3');
        final copied = result!.copyWith(codigoBarras: '00123');
        final command = ArticuloFormResult(
          nombre: 'Oferta',
          categoriaId: null,
          saleConfiguration: const UnitSaleConfiguration(),
          variantes: [copied],
        ).toCommand().variantes.single;
        expect(command.offerPrice.establecer, action != 'conservar');
        if (action != 'conservar') {
          expect(
            command.offerPrice.valor,
            action == 'retirar' ? isNull : '12.34',
          );
        }
      },
    );
  }
  testWidgets('editor rechaza oferta cero/exceso y bajar normal sin retirar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VariantEditorScreen(
          initialValue: const ArticuloFormVarianteResult(
            nombre: null,
            precioVenta: '20',
            costoEstandar: null,
            offerPriceMinor: 1500,
          ),
          canDelete: false,
          existingNameKeys: const {},
          inventoryUnit: const UnidadInventario(
            id: 'piece',
            code: 'piece',
            nombre: 'Pieza',
            simbolo: 'pza',
            dimension: DimensionUnidad.count,
            factorAtomico: 1,
            maximosDecimales: 0,
            activa: true,
          ),
        ),
      ),
    );
    final offer = find.byKey(const Key('variant_offer_price_field'));
    for (final value in ['0', '1.001', '21']) {
      await tester.ensureVisible(offer);
      await tester.enterText(offer, value);
      await tester.tap(find.byKey(const Key('save_variant_button')));
      await tester.pumpAndSettle();
      expect(find.byType(VariantEditorScreen), findsOneWidget);
      expect(tester.widget<TextFormField>(offer).controller!.text, value);
    }
    await tester.enterText(offer, '15');
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '14',
    );
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();
    expect(
      find.text('La oferta no puede superar el precio normal.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'captura masiva cancelar/conservar/establecer/retirar explícitos',
    (tester) async {
      CambioExplicito<String?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await capturarOfertaMasiva(
                    context,
                    actual: 1500,
                    cambio: const CambioExplicito.conservar(),
                  );
                },
                child: const Text('Oferta'),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('Oferta'));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      for (final action in ['Conservar', 'Establecer', 'Retirar']) {
        await open();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action).last);
        await tester.pumpAndSettle();
        if (action == 'Establecer') {
          await tester.enterText(
            find.byKey(const Key('bulk_offer_amount')),
            '12.34',
          );
        }
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();
        expect(result!.establecer, action != 'Conservar');
        if (action != 'Conservar') {
          expect(result!.valor, action == 'Retirar' ? isNull : '12.34');
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}
