import '../proveedores/supplier_order_detail.dart';
import '../sync/payloads/supplier_receipt_confirmed_payload.dart';
import '../../domain/inventario/inventory_quantity_codec.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../../domain/inventario/dimension_unidad.dart';
import 'ticket_document.dart';
import '../sync/payloads/supplier_order_line.dart';
import '../sync/payloads/supplier_order_json.dart';

/// Only frozen document data is used; no current catalog lookup.
class SupplierDocumentTicket {
  static String money(int? n) => n == null
      ? 'Sin precio conocido'
      : '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
  static TicketDocument build(
    SupplierOrderDetail detail, {
    SupplierReceiptConfirmedPayload? receipt,
  }) {
    final order = detail.order.document;
    String quantity(int n, SupplierOrderLine l) =>
        const InventoryQuantityCodec().formatAtomic(
          n,
          UnidadInventario(
            id: l.unitId,
            code: l.unitCodeSnapshot,
            nombre: l.unitCodeSnapshot,
            simbolo: l.unitSymbolSnapshot,
            dimension: DimensionUnidad.fromCode(l.dimension),
            factorAtomico: l.unitAtomicFactor,
            maximosDecimales: l.dimension == 'count' ? 0 : 9,
            activa: true,
          ),
        );
    final received = receipt?.items;
    final lines = order.items.where(
      (l) => received == null || received.any((i) => i.orderItemId == l.id),
    );
    return TicketDocument(
      title: receipt == null
          ? 'PEDIDO A PROVEEDOR · ESTIMADO'
          : 'RECEPCIÓN DE MERCANCÍA · REAL',
      identifier: receipt?.receiptId ?? order.orderId,
      date: DateTime.fromMillisecondsSinceEpoch(
        receipt?.occurredAtMs ?? order.occurredAtMs,
      ).toLocal().toString(),
      currency: order.currency,
      details: [
        'Proveedor: ${order.supplierNameSnapshot}',
        if (order.supplierPhoneSnapshot != null)
          'Teléfono: ${order.supplierPhoneSnapshot}',
        if (receipt != null) ...[
          'Pedido: ${order.orderId}',
          switch (detail.receiptStatuses[receipt.receiptId]) {
            'not_required' => 'Guardado local; no requiere sincronización.',
            'delivered' => 'Aceptación remota registrada.',
            'conflict' || 'rejected' => 'Operación no aceptada.',
            _ =>
              'Aplicación local; aceptación remota pendiente. Puede ser rechazada.',
          },
        ],
        if (receipt == null && order.notes != null) order.notes!,
      ],
      itemRows: [
        for (final l in lines)
          [
            '${l.productNameSnapshot}${l.variantNameSnapshot == null ? '' : ' · ${l.variantNameSnapshot}'}',
            '${money(received == null ? l.quotedPriceMinor : received.singleWhere((i) => i.orderItemId == l.id).actualPriceMinor)} / ${quantity(l.referenceQuantityAtomic, l)} ${l.unitSymbolSnapshot}',
            '${quantity(received == null ? l.quantityAtomic : received.singleWhere((i) => i.orderItemId == l.id).quantityAtomic, l)} ${l.unitSymbolSnapshot}',
            money(
              received == null
                  ? l.totalMinor
                  : received
                        .singleWhere((i) => i.orderItemId == l.id)
                        .totalMinor,
            ),
          ],
      ],
      totals: [
        ('Importe estimado del pedido', money(order.totalMinor)),
        if (receipt != null) ...[
          ('Importe real de esta recepción', money(receipt.totalMinor)),
          (
            'Acumulado recibido hasta este documento',
            money(
              orderTotal(
                detail.receipts
                    .take(
                      detail.receipts.indexWhere(
                            (r) => r.receiptId == receipt.receiptId,
                          ) +
                          1,
                    )
                    .map((r) => r.totalMinor),
              ),
            ),
          ),
        ],
      ],
      footer:
          'Documento informativo. Compartir o imprimir no acredita entrega al proveedor.',
    );
  }
}
