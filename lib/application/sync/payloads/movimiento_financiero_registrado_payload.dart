import 'cash_binding_payload.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../domain/finanzas/financial_direction.dart';
import '../../../domain/finanzas/financial_nature.dart';
import '../local_event_store.dart';
import 'categoria_financiera_creada_payload.dart';
import 'inventory_movement_payload.dart';

/// Máximo entero seguro (9007199254740991): límite superior de importes y
/// fechas, igual que `Number.MAX_SAFE_INTEGER` en el servidor.
const maxAmountMinor = 9007199254740991;

/// Payload tipado de `movimiento_financiero_registrado` (contrato §5.2). El
/// registro referencia la categoría por `category_id` y su evento de creación
/// por `category_event_id` (dependencia causal, contrato §3.4). `direction` y
/// `nature` se validan como valores permitidos aquí; su coincidencia con la
/// categoría se verifica en el handler. Espejo de
/// `MovimientoFinancieroRegistradoPayload` de NestJS.
class MovimientoFinancieroRegistradoPayload {
  MovimientoFinancieroRegistradoPayload._({
    required this.categoryId,
    this.cash,
    required this.categoryEventId,
    required this.categoryNameSnapshot,
    required this.direction,
    required this.nature,
    required this.amountMinor,
    required this.currency,
    required this.method,
    required this.occurredAtMs,
    required this.notes,
    required this.reference,
  });

  static const aggregateType = 'financial_entry';
  static const eventType = 'movimiento_financiero_registrado';

  final CashBindingPayload? cash;
  final String categoryId;
  final String categoryEventId;
  final String categoryNameSnapshot;
  final FinancialDirection direction;
  final FinancialNature nature;
  final int amountMinor;
  final String currency;
  final String method;
  final int occurredAtMs;
  final String? notes;
  final String? reference;

  List<String> get dependencyEventIds => [
    categoryEventId,
    if (cash != null) cash!.openingEventId,
  ];

  factory MovimientoFinancieroRegistradoPayload.fromJson(
    Map<String, Object?> json,
  ) {
    final categoryId = InventoryMovementPayload.requiredUuidV4(
      json['category_id'] as String? ?? '',
      'category_id',
    );
    final categoryEventId = InventoryMovementPayload.requiredUuidV4(
      json['category_event_id'] as String? ?? '',
      'category_event_id',
    );
    final categoryNameSnapshot = financialRequiredText(
      json['category_name_snapshot'],
      'category_name_snapshot',
      100,
    );
    final direction = financialDirection(json['direction']);
    final nature = financialNature(json['nature']);
    final amountMinor = financialAmountMinor(json['amount_minor']);
    financialCurrency(json['currency']);
    final method = financialMethod(json['method']);
    final occurredAtMs = financialOccurredAtMs(json['occurred_at_ms']);
    final notes = financialOptionalText(json['notes'], 'notes', 500);
    final reference = financialOptionalText(
      json['reference'],
      'reference',
      500,
    );
    return MovimientoFinancieroRegistradoPayload._(
      cash: CashBindingPayload.optional(json['cash'], method, amountMinor),
      categoryId: categoryId,
      categoryEventId: categoryEventId,
      categoryNameSnapshot: categoryNameSnapshot,
      direction: direction,
      nature: nature,
      amountMinor: amountMinor,
      currency: 'MXN',
      method: method,
      occurredAtMs: occurredAtMs,
      notes: notes,
      reference: reference,
    );
  }

  Map<String, Object?> toJson() => {
    if (cash != null) 'cash': cash!.toJson(),
    'category_id': categoryId,
    'category_event_id': categoryEventId,
    'category_name_snapshot': categoryNameSnapshot,
    'direction': direction.code,
    'nature': nature.code,
    'amount_minor': amountMinor,
    'currency': currency,
    'method': method,
    'occurred_at_ms': occurredAtMs,
    'notes': notes,
    'reference': reference,
  };

  /// Refs declaradas y validadas en ambos modos; standalone no las persiste
  /// (contrato §3.3): `affects` al registro y `uses` a la categoría.
  List<LocalEventRef> refs(String id) => [
    ...?cash?.refs,
    LocalEventRef.affects(refType: aggregateType, refId: id),
    LocalEventRef.uses(refType: 'financial_category', refId: categoryId),
  ];
}

/// Texto requerido NFKC+trim de 1..maxLength code points (espejo de
/// `normalizeRequiredText` para `category_name_snapshot`, contrato §5.2).
String financialRequiredText(Object? value, String fieldName, int maxLength) {
  if (value is! String) {
    throw FormatException('$fieldName debe ser texto.');
  }
  final normalized = unorm.nfkc(value).trim();
  final length = normalized.runes.length;
  if (length < 1 || length > maxLength) {
    throw FormatException(
      '$fieldName debe tener entre 1 y $maxLength caracteres.',
    );
  }
  return normalized;
}

/// Importe en centavos: entero seguro positivo (contrato §2.3).
int financialAmountMinor(Object? value) {
  if (value is! int || value < 1 || value > maxAmountMinor) {
    throw const FormatException(
      'amount_minor debe ser un entero positivo en centavos.',
    );
  }
  return value;
}

/// Moneda fija `MXN`.
String financialCurrency(Object? value) {
  if (value != 'MXN') {
    throw const FormatException('Moneda inválida.');
  }
  return 'MXN';
}

/// Medio `cash` | `transfer`.
String financialMethod(Object? value) {
  if (value is! String || (value != 'cash' && value != 'transfer')) {
    throw const FormatException('method debe ser cash o transfer.');
  }
  return value;
}

/// Instante efectivo UTC en ms: entero seguro > 0 (contrato §2.4).
int financialOccurredAtMs(Object? value) {
  if (value is! int || value < 1 || value > maxAmountMinor) {
    throw const FormatException('occurred_at_ms debe ser un instante válido.');
  }
  return value;
}
