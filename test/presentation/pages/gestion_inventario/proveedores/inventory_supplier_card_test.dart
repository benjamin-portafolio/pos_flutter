import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/proveedores/proveedor.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/proveedores/widgets/inventory_supplier_card.dart';

void main() {
  const proveedor = Proveedor(
    id: 'supplier',
    nombre: 'Norte',
    telefono: '555 0000',
    notas: 'Entrega semanal',
    version: 1,
    createdEventId: null,
    lastEventId: null,
    lastServerSequence: null,
  );

  testWidgets('muestra margen, datos y conserva la navegación', (tester) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventorySupplierCard(
            proveedor: proveedor,
            margenPromedioPorcentaje: 32.456,
            onOpen: () => opens++,
          ),
        ),
      ),
    );

    expect(find.text('Margen promedio: 32.5 %'), findsOneWidget);
    expect(find.text('555 0000\nEntrega semanal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('supplier_supplier')));
    expect(opens, 1);
  });

  testWidgets('sin datos no muestra cero por ciento', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventorySupplierCard(proveedor: proveedor, onOpen: () {}),
        ),
      ),
    );

    expect(find.text('Margen promedio: Sin datos'), findsOneWidget);
    expect(find.text('Margen promedio: 0.0 %'), findsNothing);
  });

  testWidgets('distingue carga y error sin valores ficticios', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventorySupplierCard(
            proveedor: proveedor,
            margenCargando: true,
            onOpen: () {},
          ),
        ),
      ),
    );
    expect(find.text('Margen promedio: Cargando...'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventorySupplierCard(
            proveedor: proveedor,
            margenError: true,
            onOpen: () {},
          ),
        ),
      ),
    );
    expect(find.text('Margen promedio: No disponible'), findsOneWidget);
  });

  testWidgets('adapta nombre largo y texto escalado sin perder acciones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: InventorySupplierCard(
              proveedor: const Proveedor(
                id: 'long',
                nombre: 'Proveedor con un nombre extraordinariamente largo',
                notas:
                    'Notas extensas que deben adaptarse al espacio disponible',
                version: 1,
                createdEventId: null,
                lastEventId: null,
                lastServerSequence: null,
              ),
              margenPromedioPorcentaje: -20,
              onOpen: () => opens++,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Margen promedio: -20.0 %'), findsOneWidget);
    await tester.tap(find.byKey(const Key('supplier_long')));
    expect(opens, 1);
  });
}
