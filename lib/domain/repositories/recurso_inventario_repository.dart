import '../inventario/inventory_resource_filter.dart';
import '../inventario/recurso_inventario_listado.dart';

abstract interface class RecursoInventarioRepository {
  Stream<List<RecursoInventarioListado>> watchRecursos({
    String busqueda = '',
    InventoryResourceFilter filtro = InventoryResourceFilter.all,
  });

  /// Recurso activo identificado por `id` con su saldo vigente, o `null` si ya
  /// no existe o dejó de estar activo. Permite observar un solo recurso sin
  /// recorrer el listado completo.
  Stream<RecursoInventarioListado?> watchRecursoPorId(String id);
}
