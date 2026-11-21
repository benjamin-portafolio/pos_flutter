import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_result.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';

const unit = UnidadInventario(
  id: '10000000-0000-4000-8000-000000000003',
  code: 'kg',
  nombre: 'Kilogramo',
  simbolo: 'kg',
  dimension: DimensionUnidad.mass,
  factorAtomico: 1000,
  maximosDecimales: 3,
  activa: true,
);
const sid = '20000000-0000-4000-8000-000000000001';
void main() {
  for (final width in [320.0, 1024.0]) {
    testWidgets(
      'P06 editor $width: unidad, cero/null, selección explícita y cancelar',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        ArticuloFormVarianteResult? saved;
        final original = ArticuloFormVarianteResult.conProveedores(
          nombre: null,
          precioVenta: '10',
          costoEstandar: null,
          inventoryUnitId: unit.id,
          minimumStockAtomic: 2000,
          targetStockAtomic: 1500,
          proveedores: [
            ProveedorVariante(
              proveedorId: sid,
              precioInformadoMenor: 0,
              fechaInformadaMs: 100,
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => VariantEditorScreen(
                        initialValue: original,
                        canDelete: false,
                        existingNameKeys: const {},
                        inventoryUnit: unit,
                        onSave: (value) async => saved = value,
                      ),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );
        Future<void> open() async {
          await tester.tap(find.text('Abrir'));
          await tester.pumpAndSettle();
        }

        Future<void> enter(String value) async {
          final f = find.byKey(const Key('variant_target_stock_field'));
          await tester.ensureVisible(f);
          await tester.enterText(f, value);
          await tester.pump();
        }

        await open();
        final field = tester.widget<TextFormField>(
          find.byKey(const Key('variant_target_stock_field')),
        );
        expect(field.controller!.text, '1.5');
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('variant_target_stock_field')),
                  matching: find.byType(TextField),
                ),
              )
              .decoration!
              .suffixText,
          'kg',
        );
        await enter('1.0001');
        await tester.tap(find.byKey(const Key('save_variant_button')));
        await tester.pumpAndSettle();
        expect(saved, isNull);
        await enter('0');
        final selector = find.byKey(
          const Key('variant_current_supplier_field'),
        );
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(sid).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save_variant_button')));
        await tester.pumpAndSettle();
        expect(saved!.targetStock.valor, '0');
        expect(saved!.currentSupplier.valor, sid);
        expect(saved!.minimumStock.establecer, isFalse);
        saved = null;
        await open();
        await enter('');
        await tester.tap(find.byKey(const Key('save_variant_button')));
        await tester.pumpAndSettle();
        expect(saved!.targetStock.valor, isNull);
        expect(saved!.currentSupplier.establecer, isFalse);
        saved = null;
        await open();
        await enter('7');
        await tester.tap(find.byKey(const Key('close_variant_editor_button')));
        await tester.pumpAndSettle();
        expect(saved, isNull);
        await open();
        await tester.tap(find.byKey(const Key('save_variant_button')));
        await tester.pumpAndSettle();
        expect(saved!.targetStock.establecer, isFalse);
        expect(saved!.currentSupplier.establecer, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('copyWith y comando conservan intenciones independientes', () {
    const initial = ArticuloFormVarianteResult(
      nombre: null,
      precioVenta: '10',
      costoEstandar: null,
      targetStockAtomic: 0,
      currentSupplierId: sid,
    );
    final changed = initial
        .copyWith(targetStock: const CambioExplicito.establecer(null))
        .copyWith(precioVenta: '12');
    expect(changed.targetStock.establecer, isTrue);
    expect(changed.targetStock.valor, isNull);
    expect(changed.currentSupplier.establecer, isFalse);
    expect(changed.currentSupplierId, sid);
  });
}
