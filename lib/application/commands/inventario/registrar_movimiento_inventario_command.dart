import '../../../domain/inventario/tipo_movimiento_inventario.dart';

/// Intención de registrar solo un movimiento sobre un recurso de inventario ya
/// existente. No transporta nombre ni unidad: el acceso desde el editor de
/// variantes no puede cambiar esos datos del recurso.
class RegistrarMovimientoInventarioCommand {
  const RegistrarMovimientoInventarioCommand({
    required this.inventoryItemId,
    required this.movementType,
    required this.quantityDeltaAtomic,
    this.movementReason,
  });

  final String inventoryItemId;
  final TipoMovimientoInventario movementType;
  final int quantityDeltaAtomic;
  final String? movementReason;
}
