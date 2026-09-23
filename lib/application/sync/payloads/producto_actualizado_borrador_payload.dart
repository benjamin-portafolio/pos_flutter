import 'sale_item_snapshot.dart';

/// Evento exclusivamente local. Nunca se promueve a pendiente de envío.
/// Corrige la cantidad absoluta de una línea del borrador conservando las
/// condiciones capturadas (precio, unidad, variante).
class ProductoActualizadoBorradorPayload {
  ProductoActualizadoBorradorPayload({
    required String saleItemId,
    required this.item,
  }) : saleItemId = saleItemId.trim() {
    if (this.saleItemId.isEmpty) {
      throw const FormatException('Línea de venta inválida.');
    }
  }

  static const aggregateType = 'sale_draft';
  static const eventType = 'producto_actualizado_borrador';

  final String saleItemId;

  /// Snapshot absoluto resultante; reaplicar no cambia la cantidad dos veces.
  final SaleItemSnapshot item;

  Map<String, Object?> toJson() => {
    'sale_item_id': saleItemId,
    ...item.toJson(),
  };

  factory ProductoActualizadoBorradorPayload.fromJson(
    Map<String, Object?> json,
  ) {
    if (json['sale_item_id'] is! String) {
      throw const FormatException('Línea de venta inválida.');
    }
    return ProductoActualizadoBorradorPayload(
      saleItemId: json['sale_item_id']! as String,
      item: SaleItemSnapshot.fromJson(json),
    );
  }
}