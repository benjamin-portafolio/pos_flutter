class CostoEstandar {
  const CostoEstandar._(this.unidadMenor);

  static const maxUnidadMenor = 9007199254740991;

  static CostoEstandar? fromInput(String? input) {
    final normalized = (input ?? '').trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) {
      throw ArgumentError.value(
        input,
        'costoEstandar',
        'Debe ser un importe no negativo con hasta dos decimales.',
      );
    }

    final parts = normalized.split('.');
    final whole = int.parse(parts.first);
    final decimals = parts.length == 1
        ? 0
        : int.parse(parts.last.padRight(2, '0'));
    return CostoEstandar.fromUnidadMenor(whole * 100 + decimals);
  }

  factory CostoEstandar.fromUnidadMenor(int value) {
    if (value < 0 || value > maxUnidadMenor) {
      throw ArgumentError.value(
        value,
        'costoEstandar',
        'Debe estar entre 0 y $maxUnidadMenor unidades monetarias menores.',
      );
    }
    return CostoEstandar._(value);
  }

  final int unidadMenor;
}
