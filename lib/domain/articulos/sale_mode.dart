enum SaleMode {
  unit('unit'),
  measured('measured');

  const SaleMode(this.code);

  final String code;

  static SaleMode fromCode(String code) => switch (code) {
    'unit' => SaleMode.unit,
    'measured' => SaleMode.measured,
    _ => throw ArgumentError.value(code, 'code', 'Modo de venta desconocido.'),
  };
}
