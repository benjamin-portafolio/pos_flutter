import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/sale_item_snapshot.dart';

void main() {
  SaleItemSnapshot measured({
    int quantity = 1,
    int price = 1,
    int reference = 3,
  }) => SaleItemSnapshot(
    variantId: 'variant',
    productName: 'Granel',
    saleMode: 'measured',
    quantity: null,
    measuredQuantityAtomic: quantity,
    unitPriceMinor: price,
    standardCostMinor: null,
    priceReferenceQuantityAtomic: reference,
    unitCode: 'kg',
    unitSymbol: 'kg',
    unitAtomicFactor: 1000,
  );

  test('conserva cero manual, half-up y redondeo sobre el acumulado', () {
    final gram = measured();
    expect(gram.totalMinor, 0);
    expect(gram.plus(gram).totalMinor, 1);
    expect(measured(reference: 2).totalMinor, 1);
    expect(
      measured(quantity: 333, price: 6000, reference: 1000).totalMinor,
      1998,
    );
    expect(gram.withQuantity(atomic: 4).totalMinor, 1);
  });

  test(
    'conserva JSON y agrupación con precio, referencia y unidad capturados',
    () {
      final original = measured(quantity: 334, price: 6000, reference: 1000);
      final json = original.toJson();
      expect(json, {
        'variant_id': 'variant',
        'consumption_configuration_key': null,
        'product_name_snapshot': 'Granel',
        'variant_name_snapshot': null,
        'sale_mode_snapshot': 'measured',
        'quantity': null,
        'measured_quantity_atomic': 334,
        'unit_price_minor': 6000,
        'standard_cost_minor_snapshot': null,
        'price_reference_quantity_atomic_snapshot': 1000,
        'sale_unit_code_snapshot': 'kg',
        'sale_unit_symbol_snapshot': 'kg',
        'sale_unit_atomic_factor_snapshot': 1000,
      });
      final restored = SaleItemSnapshot.fromJson(json);
      expect(restored.toJson(), json);
      expect(restored.sameConditions(original), isTrue);
      expect(restored.plus(original).measuredQuantityAtomic, 668);
      expect(restored.plus(original).totalMinor, 4008);
      for (final changes in [
        {'unit_price_minor': 8000},
        {'price_reference_quantity_atomic_snapshot': 100},
        {'sale_unit_code_snapshot': 'g', 'sale_unit_atomic_factor_snapshot': 1},
      ]) {
        expect(
          original.sameConditions(
            SaleItemSnapshot.fromJson({...json, ...changes}),
          ),
          isFalse,
        );
      }
    },
  );

  test('conserva piezas y su límite de total', () {
    final pieces = SaleItemSnapshot(
      variantId: 'variant',
      productName: 'Pieza',
      saleMode: 'unit',
      quantity: 3,
      measuredQuantityAtomic: null,
      unitPriceMinor: 3500,
      standardCostMinor: null,
      priceReferenceQuantityAtomic: null,
      unitCode: null,
      unitSymbol: null,
      unitAtomicFactor: null,
    );
    expect(pieces.totalMinor, 10500);
    expect(
      SaleItemSnapshot.fromJson(pieces.toJson()).toJson(),
      pieces.toJson(),
    );
    expect(
      () => SaleItemSnapshot.fromJson({
        ...pieces.toJson(),
        'unit_price_minor': SaleItemSnapshot.maxInteger,
      }),
      throwsFormatException,
    );
  });
}
