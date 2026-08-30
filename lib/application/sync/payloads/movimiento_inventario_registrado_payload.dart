import 'inventory_movement_payload.dart';

class MovimientoInventarioRegistradoPayload {
  const MovimientoInventarioRegistradoPayload({
    required this.baseEventId,
    required this.movement,
  });

  static const aggregateType = 'inventory_item';
  static const eventType = 'movimiento_inventario_registrado';

  final String baseEventId;
  final InventoryMovementPayload movement;

  factory MovimientoInventarioRegistradoPayload.create({
    required String baseEventId,
    required InventoryMovementPayload movement,
  }) {
    final normalizedBase = baseEventId.trim();
    if (normalizedBase.isEmpty) {
      throw const FormatException('base_event_id es obligatorio.');
    }
    return MovimientoInventarioRegistradoPayload(
      baseEventId: normalizedBase,
      movement: movement,
    );
  }

  factory MovimientoInventarioRegistradoPayload.fromJson(
    Map<String, Object?> json,
  ) {
    final baseEventId = json['base_event_id'];
    if (baseEventId is! String || baseEventId.trim().isEmpty) {
      throw const FormatException('base_event_id es obligatorio.');
    }
    final movement = json['movement'];
    if (movement is! Map) {
      throw const FormatException('movement debe ser un objeto.');
    }
    return MovimientoInventarioRegistradoPayload.create(
      baseEventId: baseEventId,
      movement: InventoryMovementPayload.fromJson(
        movement.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'movement': movement.toJson(),
  };
}
