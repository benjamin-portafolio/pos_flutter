enum TipoMovimientoInventario {
  initialBalance('initial_balance'),
  stockReceipt('stock_receipt'),
  manualAdjustment('manual_adjustment'),
  reversal('reversal');

  const TipoMovimientoInventario(this.code);

  final String code;

  static TipoMovimientoInventario fromCode(String code) {
    return TipoMovimientoInventario.values.firstWhere(
      (value) => value.code == code,
      orElse: () => throw const FormatException(
        'movement_type no pertenece a los tipos de inventario permitidos.',
      ),
    );
  }
}
