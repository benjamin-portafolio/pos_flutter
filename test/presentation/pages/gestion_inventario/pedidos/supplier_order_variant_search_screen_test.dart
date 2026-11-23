import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/proveedores/replenishment_candidate.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_order_variant_search_screen.dart';

ReplenishmentCandidate candidate(String id, String name, String? variant) =>
    ReplenishmentCandidate(
      productId: 'product-$id',
      variantId: id,
      productName: name,
      variantName: variant,
      inventoryItemId: 'inventory-$id',
      unitId: 'piece',
      unitCode: 'pza',
      unitSymbol: 'pza',
      dimension: 'count',
      atomicFactor: 1,
      referenceAtomic: 1,
      supplierId: 'supplier',
      supplierName: 'Principal',
      supplierPhone: null,
      currentSupplierId: 'supplier',
      targetAtomic: null,
      balanceAtomic: 8,
      pendingAtomic: 0,
      priceMinor: 2400,
      basis: 'basis-$id',
    );

void main() {
  for (final width in [320.0, 1024.0]) {
    testWidgets('busca y devuelve una variante a $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = [
        candidate('rice-small', 'Arroz', 'Bolsa de 1 kg'),
        candidate('rice-large', 'Arroz', 'Bolsa de 5 kg'),
        candidate('beans', 'Frijol', null),
      ];
      ReplenishmentCandidate? selected;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.of(context)
                      .push<ReplenishmentCandidate>(
                        MaterialPageRoute(
                          builder: (_) => SupplierOrderVariantSearchScreen(
                            supplierName: 'Principal',
                            candidates: rows,
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
      expect(find.text('Proveedor: Principal'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.textContaining('Existencias: 8 pza'), findsNWidgets(3));
      expect(
        find.textContaining(r'Precio de compra: $24.00 por 1 pza'),
        findsNWidgets(3),
      );

      final search = find.widgetWithText(
        TextField,
        'Buscar producto o variante',
      );
      await tester.enterText(search, '  ARROZ  ');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));
      await tester.enterText(search, '5 KG');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      await tester.enterText(search, 'sin coincidencias');
      await tester.pumpAndSettle();
      expect(find.text('No se encontraron variantes.'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(3));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(selected, isNull);

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rice-large')));
      await tester.pumpAndSettle();
      expect(selected, same(rows[1]));
      expect(find.byType(SupplierOrderVariantSearchScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
