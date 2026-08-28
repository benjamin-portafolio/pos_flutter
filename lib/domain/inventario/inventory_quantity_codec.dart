import 'unidad_inventario.dart';

class InventoryQuantityCodec {
  const InventoryQuantityCodec();

  static final BigInt _maxSafeInteger = BigInt.from(9007199254740991);

  int parsePositiveAtomic(String input, UnidadInventario unit) {
    final atomic = _parseAtomic(input, unit);
    if (atomic == 0) {
      throw const FormatException('La cantidad debe ser mayor que cero.');
    }
    return atomic;
  }

  int parseNonNegativeAtomic(String input, UnidadInventario unit) {
    return _parseAtomic(input, unit);
  }

  int _parseAtomic(String input, UnidadInventario unit) {
    final normalized = input.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      throw const FormatException('Ingresa una cantidad.');
    }
    if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(normalized)) {
      throw const FormatException('Ingresa una magnitud positiva sin signo.');
    }

    final parts = normalized.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > unit.maximosDecimales) {
      throw FormatException(
        '${unit.nombre} admite hasta ${unit.maximosDecimales} decimales.',
      );
    }

    final denominator = _powerOfTen(fraction.length);
    final numerator = BigInt.parse('${parts[0]}$fraction');
    final scaled = numerator * BigInt.from(unit.factorAtomico);
    if (scaled.remainder(denominator) != BigInt.zero) {
      throw FormatException(
        'La cantidad no es representable en átomos de ${unit.dimension.label.toLowerCase()}.',
      );
    }
    final atomic = scaled ~/ denominator;
    if (atomic > _maxSafeInteger) {
      throw const FormatException('La cantidad excede el límite permitido.');
    }
    return atomic.toInt();
  }

  String formatAtomic(int atomic, UnidadInventario unit) {
    final negative = atomic < 0;
    final magnitude = BigInt.from(atomic).abs();
    final factor = BigInt.from(unit.factorAtomico);
    final whole = magnitude ~/ factor;
    final remainder = magnitude.remainder(factor);
    if (remainder == BigInt.zero) {
      return '${negative ? '−' : ''}$whole';
    }

    final scale = _powerOfTen(unit.maximosDecimales);
    final scaledFraction = remainder * scale;
    if (scaledFraction.remainder(factor) != BigInt.zero) {
      throw StateError('El saldo atómico no es representable en ${unit.code}.');
    }
    var fraction = (scaledFraction ~/ factor).toString().padLeft(
      unit.maximosDecimales,
      '0',
    );
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    return '${negative ? '−' : ''}$whole.$fraction';
  }

  BigInt _powerOfTen(int exponent) => BigInt.from(10).pow(exponent);
}
