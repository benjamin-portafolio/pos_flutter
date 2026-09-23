class ActualizarProductoBorradorCommand {
  const ActualizarProductoBorradorCommand({
    required this.saleItemId,
    this.quantity,
    this.measuredQuantity,
  });

  final String saleItemId;

  /// Piezas finales de la línea; obligatorio cuando la venta es por unidades.
  final int? quantity;

  /// Cantidad capturada en la unidad visible, convertida en el servicio;
  /// obligatorio cuando la venta es medida.
  final String? measuredQuantity;
}