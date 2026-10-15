/// Convierte importes y cantidades medidas sin fracciones de átomo ni double.
class MeasuredSaleCalculator {
  const MeasuredSaleCalculator();

  static const maxInteger = 9007199254740991;

  /// Cantidad mínima cuyo valor proporcional alcanza el importe objetivo.
  /// Valida también el cobro resultante, que puede exceder el objetivo.
  int quantityAtomicForAmount({
    required int targetAmountMinor,
    required int unitPriceMinor,
    required int priceReferenceQuantityAtomic,
  }) {
    _positive(targetAmountMinor);
    _positive(unitPriceMinor);
    _positive(priceReferenceQuantityAtomic);
    final amount = BigInt.from(targetAmountMinor);
    final price = BigInt.from(unitPriceMinor);
    final reference = BigInt.from(priceReferenceQuantityAtomic);
    final quantity = (amount * reference + price - BigInt.one) ~/ price;
    if (quantity > BigInt.from(maxInteger)) {
      throw const FormatException('La cantidad excede el límite permitido.');
    }
    final atomic = quantity.toInt();
    totalMinor(
      unitPriceMinor: unitPriceMinor,
      quantityAtomic: atomic,
      priceReferenceQuantityAtomic: priceReferenceQuantityAtomic,
    );
    return atomic;
  }

  /// Half-up sobre la cantidad completa. Un peso manual puede dar total cero.
  int totalMinor({
    required int unitPriceMinor,
    required int quantityAtomic,
    required int priceReferenceQuantityAtomic,
  }) {
    _positive(unitPriceMinor);
    _positive(quantityAtomic);
    _positive(priceReferenceQuantityAtomic);
    final numerator = BigInt.from(unitPriceMinor) * BigInt.from(quantityAtomic);
    final denominator = BigInt.from(priceReferenceQuantityAtomic);
    final result =
        (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
    if (result > BigInt.from(maxInteger)) {
      throw const FormatException('El importe excede el límite permitido.');
    }
    return result.toInt();
  }

  static void _positive(int value) {
    if (value <= 0 || value > maxInteger) {
      throw const FormatException(
        'Cantidad o precio fuera del rango permitido.',
      );
    }
  }
}
