// Strict v1 contract helpers; no legacy adjustment events exist.
import 'inventory_movement_payload.dart';

Map<String, Object?> adjustmentObject(Object? v, List<String> keys) {
  if (v is! Map ||
      v.keys.any((k) => !keys.contains(k)) ||
      keys.any((k) => !v.containsKey(k))) {
    throw const FormatException('Objeto de ajuste inválido.');
  }
  return Map<String, Object?>.from(v);
}

int adjustmentInt(Object? v, [int min = 0]) {
  if (v is! int || v < min || v > 9007199254740991) {
    throw const FormatException('Entero fuera de rango.');
  }
  return v;
}

String adjustmentId(Object? v) {
  if (v is! String) throw const FormatException('UUID requerido.');
  return InventoryMovementPayload.requiredUuidV4(v, 'adjustment_id');
}

String adjustmentText(Object? v) {
  if (v is! String || v.trim().isEmpty || v.trim().length > 500) {
    throw const FormatException('Texto requerido.');
  }
  return v.trim();
}

String adjustmentChoice(Object? v, List<String> choices) {
  if (v is! String || !choices.contains(v)) {
    throw const FormatException('Opción inválida.');
  }
  return v;
}

List<T> adjustmentList<T>(Object? v, T Function(Object?) parse) {
  if (v is! List) throw const FormatException('Lista requerida.');
  return List.unmodifiable(v.map(parse));
}

bool adjustmentBool(Object? v) {
  if (v is! bool) throw const FormatException('Boolean requerido.');
  return v;
}

int adjustmentOffset(Object? v) {
  if (v is! int || v < -840 || v > 840) {
    throw const FormatException('Offset inválido.');
  }
  return v;
}

void adjustmentBusinessDate(
  int occurredAtMs,
  int utcOffsetMinutes,
  String businessDate,
) {
  if (occurredAtMs <= 0 || occurredAtMs > 253402249199999) {
    throw const FormatException('Fecha fuera de rango.');
  }
  final d = DateTime.fromMillisecondsSinceEpoch(
    occurredAtMs,
    isUtc: true,
  ).add(Duration(minutes: utcOffsetMinutes));
  final day =
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  if (day != businessDate) {
    throw const FormatException('Fecha de negocio inconsistente.');
  }
}
