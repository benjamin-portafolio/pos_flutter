import '../inventario/inventory_resource_filter.dart';
import '../inventario/recurso_inventario_listado.dart';

abstract interface class RecursoInventarioRepository {
  Stream<List<RecursoInventarioListado>> watchRecursos({
    String busqueda = '',
    InventoryResourceFilter filtro = InventoryResourceFilter.all,
  });
}
