import 'sale_draft_item.dart';
import 'adjusted_sale.dart';
import 'sale_adjustment_document.dart';
import 'sale_adjustment_status.dart';

/// Recibo de negocio conservado aun cuando la entrega requiera atención.
class ConfirmedSale {
  ConfirmedSale({
    required this.id,
    this.paymentMethod = 'cash',
    this.paymentReference,
    this.clienteId,
    this.clienteNombre,
    required this.createdAt,
    required this.totalMinor,
    required this.receivedMinor,
    required this.changeMinor,
    required this.currency,
    required this.deliveryStatus,
    required this.reason,
    this.adjustments = const [],
    this.adjustmentStatus = SaleAdjustmentStatus.current,
    required List<SaleDraftItem> items,
  }) : items = List.unmodifiable(items);
  final String id, currency, deliveryStatus, paymentMethod;
  final String? clienteId, clienteNombre, paymentReference;
  bool get isCredit => paymentMethod == 'credit';
  final DateTime createdAt;
  final int totalMinor, receivedMinor, changeMinor;
  final String? reason;
  final List<SaleDraftItem> items;
  final List<SaleAdjustmentDocument> adjustments;
  final SaleAdjustmentStatus adjustmentStatus;
  AdjustedSale get adjusted => AdjustedSale(
    original: this,
    status: adjustmentStatus,
    adjustments: adjustments,
  );
  ConfirmedSale withAdjustments(AdjustedSale sale) => ConfirmedSale(
    id: id,
    paymentMethod: paymentMethod,
    paymentReference: paymentReference,
    clienteId: clienteId,
    clienteNombre: clienteNombre,
    createdAt: createdAt,
    totalMinor: totalMinor,
    receivedMinor: receivedMinor,
    changeMinor: changeMinor,
    currency: currency,
    deliveryStatus: deliveryStatus,
    reason: reason,
    items: items,
    adjustments: sale.adjustments,
    adjustmentStatus: sale.status,
  );
}
