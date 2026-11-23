import '../../domain/inventario/movimiento_inventario.dart';
import '../../domain/inventario/dimension_unidad.dart';
import '../../domain/inventario/inventory_resource_filter.dart';
import '../../domain/inventario/recurso_inventario_listado.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../../domain/repositories/recurso_inventario_repository.dart';
import '../local/drift/app_database.dart';

class RecursoInventarioRepositoryImpl implements RecursoInventarioRepository {
  RecursoInventarioRepositoryImpl({required InventoryDao inventoryDao})
    : _inventoryDao = inventoryDao;

  final InventoryDao _inventoryDao;

  @override
  Stream<List<MovimientoInventario>> watchMovimientos(
    String inventoryItemId, {
    String? movementType,
    DateTime? desde,
    DateTime? hasta,
    int limit = 20,
  }) {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    return _inventoryDao
        .watchMovimientos(
          inventoryItemId,
          movementType: movementType,
          desde: desde,
          hasta: hasta,
          limit: limit,
        )
        .map(
          (rows) => rows
              .map((entry) {
                final row = entry.$1;
                return MovimientoInventario(
                  id: row.movementId,
                  inventoryItemId: row.inventoryItemId,
                  saleId: entry.$2,
                  saleItemId: row.saleItemId,
                  eventId: row.eventId,
                  reversalOfMovementId: row.reversalOfMovementId,
                  movementType: row.movementType,
                  quantityDeltaAtomic: row.quantityDeltaAtomic,
                  totalCostMinor: row.totalCostMinor,
                  reason: row.reason,
                  createdAtLocal: row.createdAtLocal,
                  serverSequence: row.serverSequence,
                );
              })
              .toList(growable: false),
        );
  }

  @override
  Stream<List<RecursoInventarioListado>> watchRecursos({
    String busqueda = '',
    InventoryResourceFilter filtro = InventoryResourceFilter.all,
  }) {
    return _inventoryDao
        .watchRecursos(
          busqueda: busqueda,
          filtro: switch (filtro) {
            InventoryResourceFilter.all => 'all',
            InventoryResourceFilter.products => 'products',
            InventoryResourceFilter.independent => 'independent',
            InventoryResourceFilter.ingredients => 'ingredients',
            InventoryResourceFilter.withStock => 'with_stock',
            InventoryResourceFilter.withoutStock => 'without_stock',
          },
        )
        .map((rows) => rows.map(_map).toList(growable: false));
  }

  @override
  Stream<RecursoInventarioListado?> watchRecursoPorId(String id) {
    return _inventoryDao
        .watchRecursoPorId(id)
        .map((row) => row == null ? null : _map(row));
  }

  RecursoInventarioListado _map(InventoryListingRow row) {
    return RecursoInventarioListado(
      id: row.id,
      nombre: row.name,
      activo: row.active,
      existenciaAtomica: row.quantityOnHandAtomic,
      unidadPredeterminada: UnidadInventario(
        id: row.unitId,
        code: row.unitCode,
        nombre: row.unitName,
        simbolo: row.symbol,
        dimension: DimensionUnidad.fromCode(row.dimension),
        factorAtomico: row.atomicFactor,
        maximosDecimales: row.maxFractionDigits,
        activa: row.unitActive,
      ),
    );
  }
}
