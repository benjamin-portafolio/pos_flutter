import 'sale_draft_item.dart';

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
    required List<SaleDraftItem> items,
  }) : items = List.unmodifiable(items);
  final String id, currency, deliveryStatus, paymentMethod;
  final String? clienteId, clienteNombre, paymentReference;
  bool get isCredit => paymentMethod == 'credit';
  final DateTime createdAt;
  final int totalMinor, receivedMinor, changeMinor;
  final String? reason;
  final List<SaleDraftItem> items;
}
