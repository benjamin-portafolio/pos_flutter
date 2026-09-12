import 'sale_item_snapshot.dart';

/// Evento exclusivamente local. Nunca se promueve a pendiente de envío.
/// La futura confirmación emitirá un evento nuevo con el estado consolidado.
class ProductoAgregadoBorradorPayload {
  ProductoAgregadoBorradorPayload({
    required this.saleItemId,
    required this.sortOrder,
    required this.item,
  }) {
    if (saleItemId.trim().isEmpty || sortOrder < 0) {
      throw const FormatException('Línea de venta inválida.');
    }
  }
  static const aggregateType = 'sale_draft';
  static const eventType = 'producto_agregado_borrador';
  final String saleItemId;
  final int sortOrder;

  /// Cantidad absoluta resultante, para que reaplicar no incremente dos veces.
  final SaleItemSnapshot item;
  Map<String, Object?> toJson() => {
    'sale_item_id': saleItemId,
    'sort_order': sortOrder,
    ...item.toJson(),
  };
  factory ProductoAgregadoBorradorPayload.fromJson(Map<String, Object?> json) {
    if (json['sale_item_id'] is! String || json['sort_order'] is! int) {
      throw const FormatException('Línea de venta inválida.');
    }
    return ProductoAgregadoBorradorPayload(
      saleItemId: json['sale_item_id']! as String,
      sortOrder: json['sort_order']! as int,
      item: SaleItemSnapshot.fromJson(json),
    );
  }
}
