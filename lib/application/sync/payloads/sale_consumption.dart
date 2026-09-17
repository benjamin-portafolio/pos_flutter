import 'inventory_movement_payload.dart';

/// Configuración y resultado histórico por línea/recurso. Un cero redondeado
/// conserva la configuración, pero no crea un movimiento.
class SaleConsumption {
  SaleConsumption({
    required this.inventoryItemId,
    required this.componentAtomic,
    required this.deltaAtomic,
    required this.movementId,
  }) {
    InventoryMovementPayload.requiredUuidV4(
      inventoryItemId,
      'inventory_item_id',
    );
    if (componentAtomic <= 0 ||
        componentAtomic > InventoryMovementPayload.maxSafeInteger ||
        deltaAtomic > 0 ||
        deltaAtomic < -InventoryMovementPayload.maxSafeInteger ||
        (deltaAtomic == 0) != (movementId == null)) {
      throw const FormatException('Consumo inválido.');
    }
    if (movementId != null) {
      InventoryMovementPayload.requiredUuidV4(movementId!, 'movement_id');
    }
  }
  final String inventoryItemId;
  final int componentAtomic;
  final int deltaAtomic;
  final String? movementId;
  Map<String, Object?> toJson() => {
    'inventory_item_id': inventoryItemId,
    'component_atomic': componentAtomic,
    'quantity_delta_atomic': deltaAtomic,
    'movement_id': movementId,
    'movement_type': 'sale_consumption',
    'total_cost_minor': null,
  };
  factory SaleConsumption.fromJson(Map<String, Object?> j) {
    if (j['movement_type'] != 'sale_consumption' ||
        j['total_cost_minor'] != null) {
      throw const FormatException('Tipo o costo de consumo inválido.');
    }
    return SaleConsumption(
      inventoryItemId: j['inventory_item_id'] as String,
      componentAtomic: j['component_atomic'] as int,
      deltaAtomic: j['quantity_delta_atomic'] as int,
      movementId: j['movement_id'] as String?,
    );
  }
  static int rounded(int component, int quantity, int reference) {
    final n = BigInt.from(component) * BigInt.from(quantity);
    final d = BigInt.from(reference);
    final result = (n * BigInt.two + d) ~/ (d * BigInt.two);
    if (result > BigInt.from(InventoryMovementPayload.maxSafeInteger)) {
      throw const FormatException('Consumo fuera de rango.');
    }
    return result.toInt();
  }
}
