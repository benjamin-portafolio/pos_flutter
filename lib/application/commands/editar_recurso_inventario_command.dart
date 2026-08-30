import '../../domain/inventario/tipo_movimiento_inventario.dart';

class EditarRecursoInventarioCommand {
  const EditarRecursoInventarioCommand({
    required this.inventoryItemId,
    required this.nombre,
    this.movementType,
    this.quantityDeltaAtomic,
    this.movementReason,
  });

  final String inventoryItemId;
  final String nombre;
  final TipoMovimientoInventario? movementType;
  final int? quantityDeltaAtomic;
  final String? movementReason;
}
