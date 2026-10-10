import '../../../../../domain/inventario/tipo_movimiento_inventario.dart';

/// Movimiento capturado por la sección compartida de movimientos.
///
/// `quantityDeltaAtomic` es el delta con signo del movimiento, no un saldo
/// objetivo: una reposición suma y una corrección puede restar.
class InventoryMovementDraft {
  const InventoryMovementDraft({
    required this.movementType,
    required this.quantityDeltaAtomic,
    required this.reason,
  });

  final TipoMovimientoInventario movementType;
  final int quantityDeltaAtomic;
  final String? reason;
}
