import 'sale_adjustment_payload.dart';

class VentaAnuladaPayload {
  VentaAnuladaPayload._(this.adjustment);
  static const aggregateType = 'sale';
  static const eventType = 'venta_anulada';
  final SaleAdjustmentPayload adjustment;
  factory VentaAnuladaPayload.fromJson(Map<String, Object?> json) {
    final p = SaleAdjustmentPayload.fromJson(json);
    if (p.kind != 'void' || p.schemaVersion != 1) {
      throw const FormatException('Tipo o versión inválidos.');
    }
    return VentaAnuladaPayload._(p);
  }
  Map<String, Object?> toJson() => adjustment.toJson();
}
