import '../local_event_store.dart';
import 'inventory_movement_payload.dart';

class AbonoClienteRegistradoPayload {
  AbonoClienteRegistradoPayload({
    required this.clienteId,
    required this.clienteEventId,
    required this.amountMinor,
    required this.method,
    required this.occurredAtMs,
    String? reference,
  }) : reference = reference == null || reference.trim().isEmpty
           ? null
           : reference.trim() {
    InventoryMovementPayload.requiredUuidV4(clienteId, 'cliente_id');
    InventoryMovementPayload.requiredUuidV4(clienteEventId, 'cliente_event_id');
    if (occurredAtMs <= 0 ||
        occurredAtMs > 9007199254740991 ||
        amountMinor <= 0 ||
        amountMinor > 9007199254740991 ||
        !['cash', 'transfer'].contains(method) ||
        (this.reference?.length ?? 0) > 500) {
      throw const FormatException(
        'Importe, método o referencia del abono inválido.',
      );
    }
  }
  static const aggregateType = 'customer_payment';
  static const eventType = 'abono_cliente_registrado';
  final String clienteId, clienteEventId, method;
  final String? reference;
  final int amountMinor, occurredAtMs;
  List<String> get dependencyEventIds => [clienteEventId];
  factory AbonoClienteRegistradoPayload.fromJson(Map<String, Object?> json) {
    if (json['currency'] != 'MXN') {
      throw const FormatException('Moneda inválida.');
    }
    return AbonoClienteRegistradoPayload(
      clienteId: json['cliente_id'] as String,
      clienteEventId: json['cliente_event_id'] as String,
      amountMinor: json['amount_minor'] as int,
      method: json['method'] as String,
      occurredAtMs: json['occurred_at_ms'] as int,
      reference: json['reference'] as String?,
    );
  }
  Map<String, Object?> toJson() => {
    'cliente_id': clienteId,
    'cliente_event_id': clienteEventId,
    'amount_minor': amountMinor,
    'occurred_at_ms': occurredAtMs,
    'method': method,
    'reference': reference,
    'currency': 'MXN',
  };
  List<LocalEventRef> refs(String id) => [
    LocalEventRef.affects(refType: aggregateType, refId: id),
    LocalEventRef.affects(refType: 'customer_account', refId: clienteId),
    LocalEventRef.uses(refType: 'cliente', refId: clienteId),
  ];
}
