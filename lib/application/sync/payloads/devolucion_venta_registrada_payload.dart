import 'sale_adjustment_payload.dart';

class DevolucionVentaRegistradaPayload {
  DevolucionVentaRegistradaPayload._(this.adjustment);
  static const aggregateType = 'sale';
  static const eventType = 'devolucion_venta_registrada';
  final SaleAdjustmentPayload adjustment;
  factory DevolucionVentaRegistradaPayload.fromJson(Map<String, Object?> json) {
    final p = SaleAdjustmentPayload.fromJson(json);
    if (p.kind != 'return' || p.schemaVersion != 1) {
      throw const FormatException('Tipo o versión inválidos.');
    }
    return DevolucionVentaRegistradaPayload._(p);
  }
  Map<String, Object?> toJson() => adjustment.toJson();
}
