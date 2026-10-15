import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/ventas/measured_sale_calculator.dart';

void main() {
  const calculator = MeasuredSaleCalculator();
  const max = MeasuredSaleCalculator.maxInteger;

  for (final (price, reference, amount, quantity, total) in [
    (6000, 1000, 2000, 334, 2004),
    (8000, 1000, 2000, 250, 2000),
    (1200, 100, 2000, 167, 2004),
    (4000, 1000, 1500, 375, 1500),
    (6000, 1000, 1, 1, 6),
    (1, 3, 1, 3, 1),
    (100000, 1, 1, 1, 100000),
  ]) {
    test('$amount centavos a $price por $reference átomos', () {
      final atomic = calculator.quantityAtomicForAmount(
        targetAmountMinor: amount,
        unitPriceMinor: price,
        priceReferenceQuantityAtomic: reference,
      );
      expect(atomic, quantity);
      expect(
        calculator.totalMinor(
          unitPriceMinor: price,
          quantityAtomic: atomic,
          priceReferenceQuantityAtomic: reference,
        ),
        total,
      );
    });
  }

  for (final (quantity, reference, total) in [
    (1, 3, 0),
    (1, 2, 1),
    (3, 2, 2),
    (4, 3, 1),
  ]) {
    test('half-up de $quantity / $reference centavos = $total', () {
      expect(
        calculator.totalMinor(
          unitPriceMinor: 1,
          quantityAtomic: quantity,
          priceReferenceQuantityAtomic: reference,
        ),
        total,
      );
    });
  }

  test('333 g manuales a 60 pesos/kg conservan 1998 centavos', () {
    expect(
      calculator.totalMinor(
        unitPriceMinor: 6000,
        quantityAtomic: 333,
        priceReferenceQuantityAtomic: 1000,
      ),
      1998,
    );
  });

  for (final invalid in [0, -1, max + 1]) {
    for (final field in ['amount', 'price', 'reference']) {
      test('conversión rechaza $field = $invalid', () {
        expect(
          () => calculator.quantityAtomicForAmount(
            targetAmountMinor: field == 'amount' ? invalid : 1,
            unitPriceMinor: field == 'price' ? invalid : 1,
            priceReferenceQuantityAtomic: field == 'reference' ? invalid : 1,
          ),
          throwsFormatException,
        );
      });
    }
    for (final field in ['quantity', 'price', 'reference']) {
      test('total proporcional rechaza $field = $invalid', () {
        expect(
          () => calculator.totalMinor(
            quantityAtomic: field == 'quantity' ? invalid : 1,
            unitPriceMinor: field == 'price' ? invalid : 1,
            priceReferenceQuantityAtomic: field == 'reference' ? invalid : 1,
          ),
          throwsFormatException,
        );
      });
    }
  }

  test('acepta el máximo y productos intermedios mayores que int64', () {
    expect(
      calculator.quantityAtomicForAmount(
        targetAmountMinor: max,
        unitPriceMinor: max,
        priceReferenceQuantityAtomic: max,
      ),
      max,
    );
    expect(
      calculator.totalMinor(
        unitPriceMinor: max,
        quantityAtomic: max,
        priceReferenceQuantityAtomic: max,
      ),
      max,
    );
  });

  test('rechaza cantidad calculada fuera del rango seguro', () {
    expect(
      () => calculator.quantityAtomicForAmount(
        targetAmountMinor: max,
        unitPriceMinor: 1,
        priceReferenceQuantityAtomic: max,
      ),
      throwsFormatException,
    );
  });

  test('rechaza el excedente del cobro aunque el objetivo sea seguro', () {
    expect(
      () => calculator.quantityAtomicForAmount(
        targetAmountMinor: max,
        unitPriceMinor: 2,
        priceReferenceQuantityAtomic: 1,
      ),
      throwsFormatException,
    );
  });

  test('rechaza total proporcional fuera del rango seguro', () {
    expect(
      () => calculator.totalMinor(
        unitPriceMinor: max,
        quantityAtomic: 2,
        priceReferenceQuantityAtomic: 1,
      ),
      throwsFormatException,
    );
  });
}
