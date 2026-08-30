import '../../../../../domain/inventario/unidad_inventario.dart';
import '../../../../../domain/inventario/tipo_movimiento_inventario.dart';

class InventoryResourceFormResult {
  const InventoryResourceFormResult({
    required this.nombre,
    required this.unidad,
    required this.quantityDeltaAtomic,
    required this.movementReason,
    required this.movementType,
  });

  final String nombre;
  final UnidadInventario unidad;
  final int? quantityDeltaAtomic;
  final String? movementReason;
  final TipoMovimientoInventario? movementType;
}
