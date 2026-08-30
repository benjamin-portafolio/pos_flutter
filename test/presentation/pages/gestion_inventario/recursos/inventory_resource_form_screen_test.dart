import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/recursos/inventory_resource_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/recursos/models/inventory_resource_form_result.dart';

void main() {
  const piece = UnidadInventario(
    id: 'piece',
    code: 'piece',
    nombre: 'Pieza',
    simbolo: 'pza',
    dimension: DimensionUnidad.count,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  );
  const kg = UnidadInventario(
    id: 'kg',
    code: 'kg',
    nombre: 'Kilogramo',
    simbolo: 'kg',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  );
  const liter = UnidadInventario(
    id: 'l',
    code: 'l',
    nombre: 'Litro',
    simbolo: 'L',
    dimension: DimensionUnidad.volume,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  );

  testWidgets('agrupa unidades y cambia vista previa verde/roja', (
    tester,
  ) async {
    InventoryResourceFormResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryResourceFormScreen(
          units: const [piece, kg, liter],
          onSave: (result) async => saved = result,
        ),
      ),
    );

    expect(find.text('AÑADIR RECURSO'), findsOneWidget);
    expect(find.text('Existencias actuales'), findsOneWidget);
    expect(find.text('Existencias actualizadas'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);

    await tester.tap(find.text('Seleccionar unidad'));
    await tester.pumpAndSettle();
    expect(find.text('Conteo'), findsOneWidget);
    expect(find.text('Masa'), findsOneWidget);
    expect(find.text('Volumen'), findsOneWidget);
    expect(find.text('Pieza (pza)'), findsOneWidget);
    expect(find.text('Kilogramo (kg)'), findsOneWidget);
    expect(find.text('Litro (L)'), findsOneWidget);

    await tester.tap(find.text('Kilogramo (kg)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('inventory_resource_name_field')),
      'Harina',
    );
    await tester.enterText(
      find.byKey(const Key('inventory_initial_quantity_field')),
      '0.25',
    );
    await tester.pump();
    expect(find.text('0.25 kg'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('inventory_stock_direction')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar stock (−)'));
    await tester.pump();
    expect(find.text('−0.25 kg'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('inventory_movement_reason_field')),
    );
    await tester.enterText(
      find.byKey(const Key('inventory_movement_reason_field')),
      '',
    );
    await tester.ensureVisible(
      find.byKey(const Key('save_inventory_resource_button')),
    );
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pump();
    expect(
      find.text('El motivo es obligatorio cuando capturas una cantidad.'),
      findsOneWidget,
    );
    expect(saved, isNull);

    await tester.enterText(
      find.byKey(const Key('inventory_movement_reason_field')),
      'Conteo inicial',
    );
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pumpAndSettle();

    expect(saved?.quantityDeltaAtomic, -250);
    expect(saved?.movementReason, 'Conteo inicial');
  });

  testWidgets('sin cantidad guarda sin generar movimiento cero', (
    tester,
  ) async {
    InventoryResourceFormResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryResourceFormScreen(
          units: const [piece],
          onSave: (result) async => saved = result,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('inventory_resource_name_field')),
      'Vasos',
    );
    await tester.tap(find.text('Seleccionar unidad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pieza (pza)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pumpAndSettle();

    expect(saved?.quantityDeltaAtomic, isNull);
    expect(saved?.movementReason, isNull);
  });

  testWidgets('muestra un recurso existente en modo estrictamente lectura', (
    tester,
  ) async {
    const resource = RecursoInventarioListado(
      id: 'flour',
      nombre: 'Harina',
      activo: false,
      existenciaAtomica: -250,
      unidadPredeterminada: kg,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: InventoryResourceFormScreen.readOnly(resource: resource),
      ),
    );

    expect(find.text('RECURSO DE INVENTARIO'), findsOneWidget);
    expect(find.text('Harina'), findsOneWidget);
    expect(find.text('Kilogramo (kg)'), findsOneWidget);
    expect(find.text('−0.25 kg'), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);
    expect(
      find.byKey(const Key('save_inventory_resource_button')),
      findsNothing,
    );
    expect(find.byKey(const Key('inventory_stock_direction')), findsNothing);
    expect(
      find.byKey(const Key('inventory_initial_quantity_field')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('inventory_movement_reason_field')),
      findsNothing,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('inventory_resource_name_field')),
          )
          .enabled,
      isFalse,
    );
  });
}
