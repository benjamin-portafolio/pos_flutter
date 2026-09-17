import '../local_event_store.dart';
import 'confirmed_sale_line.dart';
import 'inventory_movement_payload.dart';
import 'sale_item_snapshot.dart';

class VentaConfirmadaPayload {
  VentaConfirmadaPayload({
    required this.paymentId,
    required this.totalMinor,
    required this.receivedMinor,
    required this.changeMinor,
    required this.currency,
    required List<ConfirmedSaleLine> lines,
    required List<String> dependencyEventIds,
  }) : lines = List.unmodifiable(lines),
       dependencyEventIds = List.unmodifiable(dependencyEventIds) {
    InventoryMovementPayload.requiredUuidV4(paymentId, 'payment_id');
    for (final id in dependencyEventIds) {
      InventoryMovementPayload.requiredUuidV4(id, 'dependency');
    }
    final sum = lines.fold(
      BigInt.zero,
      (n, l) => n + BigInt.from(l.snapshot.totalMinor),
    );
    final movements = lines
        .expand((l) => l.consumptions)
        .map((c) => c.movementId)
        .whereType<String>()
        .toList();
    if (lines.isEmpty ||
        lines.map((l) => l.id).toSet().length != lines.length ||
        movements.toSet().length != movements.length ||
        sum != BigInt.from(totalMinor) ||
        totalMinor < 0 ||
        totalMinor > SaleItemSnapshot.maxInteger ||
        receivedMinor < totalMinor ||
        receivedMinor > SaleItemSnapshot.maxInteger ||
        changeMinor != receivedMinor - totalMinor ||
        currency != 'MXN' ||
        !lines.every(
          (l) => dependencyEventIds.contains(l.configurationEventId),
        )) {
      throw const FormatException('Venta, pago o total inválido.');
    }
  }
  static const aggregateType = 'sale';
  static const eventType = 'venta_confirmada';
  final String paymentId, currency;
  final int totalMinor, receivedMinor, changeMinor;
  final List<ConfirmedSaleLine> lines;
  final List<String> dependencyEventIds;
  Map<String, Object?> toJson() => {
    'payment_id': paymentId,
    'payment_method': 'cash',
    'total_minor': totalMinor,
    'received_minor': receivedMinor,
    'change_minor': changeMinor,
    'currency': currency,
    'lines': lines.map((l) => l.toJson()).toList(),
    'dependency_event_ids': dependencyEventIds,
  };
  factory VentaConfirmadaPayload.fromJson(Map<String, Object?> j) {
    if (j['payment_method'] != 'cash') {
      throw const FormatException('Solo efectivo.');
    }
    return VentaConfirmadaPayload(
      paymentId: j['payment_id'] as String,
      totalMinor: j['total_minor'] as int,
      receivedMinor: j['received_minor'] as int,
      changeMinor: j['change_minor'] as int,
      currency: j['currency'] as String,
      lines: (j['lines'] as List)
          .map(
            (l) =>
                ConfirmedSaleLine.fromJson(Map<String, Object?>.from(l as Map)),
          )
          .toList(),
      dependencyEventIds: (j['dependency_event_ids'] as List).cast<String>(),
    );
  }
  List<LocalEventRef> refs(String saleId) => [
    LocalEventRef.affects(refType: 'sale', refId: saleId),
    LocalEventRef.affects(refType: 'payment', refId: paymentId),
    for (final l in lines) ...[
      LocalEventRef.affects(refType: 'sale_item', refId: l.id),
      LocalEventRef.uses(refType: 'product', refId: l.productId),
      LocalEventRef.uses(
        refType: 'product_variant',
        refId: l.snapshot.variantId,
      ),
      LocalEventRef.uses(refType: 'recipe', refId: l.snapshot.variantId),
      if (l.saleUnitId != null)
        LocalEventRef.uses(refType: 'unit', refId: l.saleUnitId!),
      for (final c in l.consumptions) ...[
        LocalEventRef.uses(refType: 'inventory_item', refId: c.inventoryItemId),
        if (c.movementId != null)
          LocalEventRef.affects(
            refType: 'inventory_movement',
            refId: c.movementId!,
          ),
      ],
    ],
  ];
}
