/// Limpieza física local; el evento conserva la trazabilidad de las líneas.
class VentaBorradorLimpiadaPayload {
  VentaBorradorLimpiadaPayload({required List<String> saleItemIds})
    : saleItemIds = List.unmodifiable(saleItemIds.map((id) => id.trim())) {
    if (this.saleItemIds.any((id) => id.isEmpty) ||
        this.saleItemIds.toSet().length != this.saleItemIds.length) {
      throw const FormatException('Referencias de líneas inválidas.');
    }
  }

  static const aggregateType = 'sale_draft';
  static const eventType = 'venta_borrador_limpiada';
  final List<String> saleItemIds;

  Map<String, Object?> toJson() => {'sale_item_ids': saleItemIds};

  factory VentaBorradorLimpiadaPayload.fromJson(Map<String, Object?> json) {
    final ids = json['sale_item_ids'];
    if (ids is! List || ids.any((id) => id is! String)) {
      throw const FormatException('Referencias de líneas inválidas.');
    }
    return VentaBorradorLimpiadaPayload(saleItemIds: ids.cast<String>());
  }
}
