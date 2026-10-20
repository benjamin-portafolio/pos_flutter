import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/caja/weighing/sale_weighing_controller.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';

import '../../../../support/barcode_sale_fixture.dart';
import '../../../../support/fake_scale_gateway.dart';
import 'sale_weighing_controller_test.dart' show profile, weight;

void main() {
  for (final change in ['ninguno', 'precio', 'referencia', 'unidad', 'modo']) {
    test(
      'B26 resultado de ventana ante cambio $change conserva validación transaccional',
      () async {
        final fixture = BarcodeSaleFixture();
        final gateway = FakeScaleGateway();
        final service = ScaleSessionService(gateway);
        SaleWeighingController? controller;
        try {
          await fixture.seed();
          await fixture.db.productoDao.actualizarVariante(
            'M',
            const ProductVariantsCompanion(salePriceMinor: Value(5000)),
          );
          final conditions = (await fixture.products
              .obtenerCondicionesVentaMedida('M'))!;
          controller = SaleWeighingController(
            conditions: conditions,
            profile: profile,
            service: service,
            draft: Stream.value(null),
          );
          controller.start();
          await Future<void>.delayed(Duration.zero);
          gateway.reads.single.complete([weight(430)]);
          await Future<void>.delayed(Duration.zero);
          expect(controller.capture!.totalMinor, 2150);
          controller.presented(controller.revision);
          final result = controller.accept(controller.revision)!;
          await controller.stop();
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
            case 'modo':
              await fixture.db.productoDao.actualizarProducto(
                'product-M',
                const ProductsCompanion(
                  saleMode: Value('unit'),
                  saleUnitId: Value(null),
                  priceReferenceQuantityAtomic: Value(null),
                ),
              );
          }
          if (change == 'ninguno') {
            await fixture.commands.agregar(result.toCommand('M'));
            final draft = (await fixture.draft)!;
            expect(draft.items.single.measuredQuantityAtomic, 430);
            expect(draft.totalMinor, 2150);
            expect(await fixture.payloads(), hasLength(1));
          } else {
            await expectLater(
              fixture.commands.agregar(result.toCommand('M')),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'revisión explícita',
                  contains('Vuelve a seleccionar'),
                ),
              ),
            );
            await fixture.expectNoWrites();
          }
        } finally {
          controller?.dispose();
          await service.dispose();
          await fixture.dispose();
        }
      },
    );
  }
}
