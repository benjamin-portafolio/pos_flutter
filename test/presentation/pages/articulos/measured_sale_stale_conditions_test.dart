import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/articulos/article_search_screen.dart';

import '../../../support/barcode_sale_fixture.dart';

void main() {
  late BarcodeSaleFixture fixture;
  setUp(() async {
    fixture = BarcodeSaleFixture();
    await fixture.seed();
    await fixture.db.productoDao.actualizarVariante(
      'M',
      const ProductVariantsCompanion(salePriceMinor: Value(6000)),
    );
  });
  tearDown(() => fixture.dispose());

  for (final change in ['precio', 'referencia', 'unidad']) {
    testWidgets(
      'búsqueda: $change obsoleto no escribe y reabrir exige revisar condiciones',
      (tester) async {
        Future<void> settle() async {
          for (var i = 0; i < 3; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
        }

        try {
          await tester.pumpWidget(
            MaterialApp(
              home: ArticleSearchScreen(
                productoRepository: fixture.products,
                saleDraftRepository: fixture.drafts,
                ventaBorradorCommandService: fixture.commands,
              ),
            ),
          );
          await settle();
          await tester.tap(find.text('M'));
          await settle();
          await tester.enterText(
            find.byKey(const ValueKey('sale-target-amount')),
            '20',
          );
          await tester.pump();
          expect(find.text(r'Cobro por esta cantidad: $20.04'), findsOneWidget);
          await tester.runAsync(() async {
            switch (change) {
              case 'precio':
                await fixture.db.productoDao.actualizarVariante(
                  'M',
                  const ProductVariantsCompanion(salePriceMinor: Value(8000)),
                );
              case 'referencia':
                await fixture.db.productoDao.actualizarProducto(
                  'product-M',
                  const ProductsCompanion(
                    priceReferenceQuantityAtomic: Value(100),
                  ),
                );
              case 'unidad':
                await fixture.db.productoDao.actualizarProducto(
                  'product-M',
                  const ProductsCompanion(
                    saleUnitId: Value(InventoryUnitIds.gram),
                  ),
                );
            }
          });
          await tester.tap(find.text('Agregar'));
          await settle();
          expect(
            find.textContaining(
              change == 'unidad'
                  ? 'La unidad de venta cambió'
                  : 'El precio o su referencia cambió',
            ),
            findsOneWidget,
          );
          await tester.runAsync(fixture.expectNoWrites);
          expect(fixture.attempts, hasLength(1));
          await tester.tap(find.text('M'));
          await settle();
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('sale-target-amount')),
                )
                .controller!
                .text,
            isEmpty,
          );
          final priceLabel = switch (change) {
            'precio' => r'Precio: $80.00 / 1 kg',
            'referencia' => r'Precio: $60.00 / 0.1 kg',
            _ => r'Precio: $60.00 / 1000 g',
          };
          expect(find.text(priceLabel), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('sale-target-amount')),
            '20',
          );
          await tester.pump();
          expect(
            find.text(
              'Cobro por esta cantidad: ${switch (change) {
                'precio' => r'$20.00',
                'referencia' => r'$20.40',
                _ => r'$20.04',
              }}',
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Agregar'));
          await settle();
          final draft = (await tester.runAsync(() => fixture.draft))!;
          expect(draft.items.single.measuredQuantityAtomic, switch (change) {
            'precio' => 250,
            'referencia' => 34,
            _ => 334,
          });
          expect(fixture.attempts.last.targetAmountMinor, 2000);
          expect(fixture.attempts.last.measuredQuantity, isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await settle();
        }
      },
    );
  }
}
