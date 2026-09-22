import '../local_event_store.dart';
import 'confirmed_sale_line.dart';
import 'inventory_movement_payload.dart';
import 'sale_item_snapshot.dart';

class VentaConfirmadaPayload {
  VentaConfirmadaPayload({
    required this.paymentId,
    this.paymentMethod = 'cash',
    this.clienteId,
    this.clienteEventId,
    this.clienteNombre,
    this.occurredAtMs,
    required this.totalMinor,
    required this.receivedMinor,
    required this.changeMinor,
    required this.currency,
    required List<ConfirmedSaleLine> lines,
    required List<String> dependencyEventIds,
  }) : lines = List.unmodifiable(lines),
       dependencyEventIds = List.unmodifiable(dependencyEventIds) {
    if (paymentMethod == 'cash') {
      InventoryMovementPayload.requiredUuidV4(paymentId ?? '', 'payment_id');
    } else if (paymentMethod != 'credit' ||
        paymentId != null ||
        clienteId == null ||
        totalMinor <= 0) {
      throw const FormatException('Crédito inválido: selecciona un cliente.');
    }
    if (paymentMethod == 'credit' &&
        (occurredAtMs == null ||
            occurredAtMs! <= 0 ||
            occurredAtMs! > 9007199254740991)) {
      throw const FormatException('Fecha del crédito inválida.');
    }
    if (clienteId != null) {
      InventoryMovementPayload.requiredUuidV4(clienteId!, 'cliente_id');
      InventoryMovementPayload.requiredUuidV4(
        clienteEventId ?? '',
        'cliente_event_id',
      );
      if (clienteNombre == null ||
          clienteNombre!.trim().isEmpty ||
          !dependencyEventIds.contains(clienteEventId)) {
        throw const FormatException('Falta la identidad del cliente.');
      }
    } else if (clienteEventId != null || clienteNombre != null) {
      throw const FormatException('Cliente inconsistente.');
    }
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
        receivedMinor < 0 ||
        (paymentMethod == 'cash' && receivedMinor < totalMinor) ||
        receivedMinor > SaleItemSnapshot.maxInteger ||
        (paymentMethod == 'cash' &&
            changeMinor != receivedMinor - totalMinor) ||
        (paymentMethod == 'credit' &&
            (receivedMinor != 0 || changeMinor != 0)) ||
        currency != 'MXN' ||
        !lines.every(
          (l) => dependencyEventIds.contains(l.configurationEventId),
        )) {
      throw const FormatException('Venta, pago o total inválido.');
    }
  }
  static const aggregateType = 'sale';
  static const eventType = 'venta_confirmada';
  final String? paymentId, clienteId, clienteEventId, clienteNombre;
  final String currency, paymentMethod;
  bool get isCredit => paymentMethod == 'credit';
  final int totalMinor, receivedMinor, changeMinor;
  final int? occurredAtMs;
  final List<ConfirmedSaleLine> lines;
  final List<String> dependencyEventIds;
  Map<String, Object?> toJson() => {
    'payment_id': paymentId,
    'payment_method': paymentMethod,
    if (occurredAtMs != null) 'occurred_at_ms': occurredAtMs,
    if (clienteId != null) ...{
      'cliente_id': clienteId,
      'cliente_event_id': clienteEventId,
      'cliente_nombre': clienteNombre,
    },
    'total_minor': totalMinor,
    'received_minor': receivedMinor,
    'change_minor': changeMinor,
    'currency': currency,
    'lines': lines.map((l) => l.toJson()).toList(),
    'dependency_event_ids': dependencyEventIds,
  };
  factory VentaConfirmadaPayload.fromJson(Map<String, Object?> j) {
    return VentaConfirmadaPayload(
      paymentId: j['payment_id'] as String?,
      paymentMethod: j['payment_method'] as String,
      occurredAtMs: j['occurred_at_ms'] as int?,
      clienteId: j['cliente_id'] as String?,
      clienteEventId: j['cliente_event_id'] as String?,
      clienteNombre: j['cliente_nombre'] as String?,
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
    if (paymentId != null)
      LocalEventRef.affects(refType: 'payment', refId: paymentId!),
    if (isCredit) LocalEventRef.affects(refType: 'credit', refId: saleId),
    if (clienteId != null)
      LocalEventRef.uses(refType: 'cliente', refId: clienteId!),
    if (isCredit)
      LocalEventRef.affects(refType: 'customer_account', refId: clienteId!),
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
