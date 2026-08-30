import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
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
  const resource = RecursoInventarioListado(
    id: 'flour',
    nombre: 'Harina',
    activo: true,
    existenciaAtomica: 1250,
    unidadPredeterminada: kg,
  );

  testWidgets('creación usa initial_balance positivo con motivo opcional', (
    tester,
  ) async {
    InventoryResourceFormResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryResourceFormScreen(
          units: const [piece, kg],
          onSave: (result) async => saved = result,
        ),
      ),
    );

    expect(find.text('Nuevo recurso de inventario'), findsOneWidget);
    expect(find.byKey(const Key('inventory_stock_direction')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('inventory_resource_name_field')),
      'Harina',
    );
    await tester.tap(find.text('Seleccionar unidad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilogramo (kg)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('inventory_initial_quantity_field')),
      '0.25',
    );
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pumpAndSettle();

    expect(saved?.quantityDeltaAtomic, 250);
    expect(saved?.movementType, TipoMovimientoInventario.initialBalance);
    expect(saved?.movementReason, isNull);
  });

  testWidgets('edición precarga nombre, existencia y bloquea unidad', (
    tester,
  ) async {
    InventoryResourceFormResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryResourceFormScreen.edit(
          resource: resource,
          onSave: (result) async => saved = result,
        ),
      ),
    );

    expect(find.text('Editar recurso de inventario'), findsOneWidget);
    expect(find.text('1.25 kg'), findsWidgets);
    expect(
      find.text(
        'La unidad no puede cambiarse porque el historial ya utiliza esta unidad.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    final name = tester.widget<TextFormField>(
      find.byKey(const Key('inventory_resource_name_field')),
    );
    expect(name.controller?.text, 'Harina');
    expect(name.enabled, isTrue);

    await tester.enterText(
      find.byKey(const Key('inventory_resource_name_field')),
      'Harina integral',
    );
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pumpAndSettle();
    expect(saved?.nombre, 'Harina integral');
    expect(saved?.quantityDeltaAtomic, isNull);
    expect(saved?.movementType, isNull);
  });

  testWidgets('reposición predeterminada acepta motivo ausente', (
    tester,
  ) async {
    InventoryResourceFormResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryResourceFormScreen.edit(
          resource: resource,
          onSave: (result) async => saved = result,
        ),
      ),
    );

    expect(find.text('Agregar existencia'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('inventory_initial_quantity_field')),
      '0.5',
    );
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pumpAndSettle();

    expect(saved?.quantityDeltaAtomic, 500);
    expect(saved?.movementType, TipoMovimientoInventario.stockReceipt);
    expect(saved?.movementReason, isNull);
  });

  testWidgets('reposición permite un motivo rápido opcional', (tester) async {
    InventoryResourceFormResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryResourceFormScreen.edit(
          resource: resource,
          onSave: (result) async => saved = result,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('inventory_initial_quantity_field')),
      '0.5',
    );
    await tester.ensureVisible(
      find.byKey(const Key('inventory_movement_reason_choice')),
    );
    await tester.tap(find.byKey(const Key('inventory_movement_reason_choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compra').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pumpAndSettle();

    expect(saved?.quantityDeltaAtomic, 500);
    expect(saved?.movementType, TipoMovimientoInventario.stockReceipt);
    expect(saved?.movementReason, 'Compra');
  });

  testWidgets('corrección manual exige motivo y admite delta negativo', (
    tester,
  ) async {
    InventoryResourceFormResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryResourceFormScreen.edit(
          resource: resource,
          onSave: (result) async => saved = result,
        ),
      ),
    );

    await tester.tap(find.text('Corregir existencia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disminuir (−)'));
    await tester.enterText(
      find.byKey(const Key('inventory_initial_quantity_field')),
      '0.25',
    );
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pump();
    expect(
      find.text('Selecciona un motivo para la corrección manual.'),
      findsOneWidget,
    );
    expect(saved, isNull);

    await tester.ensureVisible(
      find.byKey(const Key('inventory_movement_reason_choice')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory_movement_reason_choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conteo físico').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_inventory_resource_button')));
    await tester.pumpAndSettle();

    expect(saved?.quantityDeltaAtomic, -250);
    expect(saved?.movementType, TipoMovimientoInventario.manualAdjustment);
    expect(saved?.movementReason, 'Conteo físico');
  });
}
