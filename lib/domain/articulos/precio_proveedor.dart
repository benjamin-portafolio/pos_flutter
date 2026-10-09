/// Precio informado en la moneda del POS; cero es un importe explícito.
class PrecioProveedor {
  const PrecioProveedor._(this.unidadMenor);

  static const maxUnidadMenor = 9007199254740991;

  factory PrecioProveedor.fromUnidadMenor(int value) {
    if (value < 0 || value > maxUnidadMenor) {
      throw const FormatException(
        'Precio de proveedor fuera del rango seguro.',
      );
    }
    return PrecioProveedor._(value);
  }

  final int unidadMenor;
}
