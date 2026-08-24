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
  Stream<List<RecursoInventarioListado>> watchRecursos({
    String busqueda = '',
    InventoryResourceFilter filtro = InventoryResourceFilter.all,
  }) {
    return _inventoryDao
        .watchRecursos(
          busqueda: busqueda,
          filtro: switch (filtro) {
            InventoryResourceFilter.all => 'all',
            InventoryResourceFilter.inactive => 'inactive',
          },
        )
        .map(
          (rows) => rows
              .map(
                (row) => RecursoInventarioListado(
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
                ),
              )
              .toList(growable: false),
        );
  }
}
