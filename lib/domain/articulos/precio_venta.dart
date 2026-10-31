class PrecioVenta {
  const PrecioVenta._(this.unidadMenor);

  static const maxUnidadMenor = 9007199254740991;

  factory PrecioVenta.fromInput(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) {
      throw ArgumentError.value(
        input,
        'precio',
        'Debe ser un importe con hasta dos decimales.',
      );
    }

    final parts = normalized.split('.');
    final whole = BigInt.parse(parts.first);
    final decimals = parts.length == 1
        ? 0
        : int.parse(parts.last.padRight(2, '0'));
    final unidadMenor = whole * BigInt.from(100) + BigInt.from(decimals);
    if (unidadMenor > BigInt.from(maxUnidadMenor)) {
      throw ArgumentError.value(
        input,
        'precio',
        'El importe excede el límite permitido.',
      );
    }
    return PrecioVenta.fromUnidadMenor(unidadMenor.toInt());
  }

  factory PrecioVenta.fromUnidadMenor(int value) {
    if (value <= 0 || value > maxUnidadMenor) {
      throw ArgumentError.value(
        value,
        'precio',
        'Debe estar entre 1 y $maxUnidadMenor unidades monetarias menores.',
      );
    }
    return PrecioVenta._(value);
  }

  final int unidadMenor;
}
