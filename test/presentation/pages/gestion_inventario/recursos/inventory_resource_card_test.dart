import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/recursos/widgets/inventory_resource_card.dart';

void main() {
  testWidgets('muestra saldo y estado', (tester) async {
    const unit = UnidadInventario(
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
      activo: false,
      existenciaAtomica: -250,
      unidadPredeterminada: unit,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InventoryResourceCard(resource: resource)),
      ),
    );

    expect(find.text('Harina'), findsOneWidget);
    expect(find.text('−0.25 kg'), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);
  });
}
