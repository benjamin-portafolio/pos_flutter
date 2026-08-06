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
    final whole = int.parse(parts.first);
    final decimals = parts.length == 1
        ? 0
        : int.parse(parts.last.padRight(2, '0'));
    final unidadMenor = whole * 100 + decimals;
    return PrecioVenta.fromUnidadMenor(unidadMenor);
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
