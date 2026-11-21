import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/pantalla_edicion_masiva_por_tarea.dart';
import '../../../../support/product_supplier_harness.dart';
import '../../../../support/recepcion_masiva_fixture.dart';

void main() {
  testWidgets(
    'P08 tarea Reposición: cancelar no escribe y revisar/guardar configura solo la variante capturada',
    (tester) async {
      final h = ProductSupplierHarness();
      addTearDown(h.dispose);
      final rows = await seedRecepcion(h);
      final row = rows.singleWhere((r) => r.nombreVariante == 'Piezas');
      final events = (await h.db.select(h.db.events).get()).length;
      final stock = await h.db.select(h.db.inventoryBalances).get();
      await tester.pumpWidget(
        MaterialApp(
          home: PantallaEdicionMasivaPorTarea(
            catalogo: DriftCatalogoEdicionMasiva(h.db),
            comando: coordinadorRecepcion(h),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('edicion_masiva_busqueda')),
        'Piezas',
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edicion_masiva_tarea')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reposición').last);
      await tester.pumpAndSettle();
      final edit = find.byKey(
        ValueKey('replenishment_edit_${row.clave.variantId}'),
      );
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect((await h.db.select(h.db.events).get()).length, events);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('replenishment_target_action')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('establecer').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('replenishment_target_input')),
        '7',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Revisar'),
        ),
      );
      await tester.pumpAndSettle();
      expect((await h.db.select(h.db.events).get()).length, events);
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Existencia objetivo:'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edicion_masiva_guardar')));
      await tester.pumpAndSettle();
      final state = await h.tracking.products.snapshot(row.clave.productId);
      expect(
        state.variantes
            .singleWhere((v) => v.id == row.clave.variantId)
            .replenishment
            .targetAtomic,
        7,
      );
      expect(
        state.variantes
            .where((v) => v.id != row.clave.variantId)
            .every((v) => v.replenishment.targetAtomic == null),
        isTrue,
      );
      expect(await h.db.select(h.db.inventoryBalances).get(), stock);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
