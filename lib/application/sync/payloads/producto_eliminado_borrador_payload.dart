/// Evento exclusivamente local. Nunca se promueve a pendiente de envío.
/// Elimina únicamente la línea indicada del borrador en preparación.
class ProductoEliminadoBorradorPayload {
  ProductoEliminadoBorradorPayload({required String saleItemId})
    : saleItemId = saleItemId.trim() {
    if (this.saleItemId.isEmpty) {
      throw const FormatException('Línea de venta inválida.');
    }
  }

  static const aggregateType = 'sale_draft';
  static const eventType = 'producto_eliminado_borrador';

  final String saleItemId;

  Map<String, Object?> toJson() => {'sale_item_id': saleItemId};

  factory ProductoEliminadoBorradorPayload.fromJson(
    Map<String, Object?> json,
  ) {
    final saleItemId = json['sale_item_id'];
    if (saleItemId is! String) {
      throw const FormatException('Línea de venta inválida.');
    }
    return ProductoEliminadoBorradorPayload(saleItemId: saleItemId);
  }
}