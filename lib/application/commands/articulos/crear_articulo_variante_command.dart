import 'crear_articulo_recipe_component_command.dart';

class CrearArticuloVarianteCommand {
  const CrearArticuloVarianteCommand({
    required this.nombre,
    required this.precioVenta,
    required this.costoEstandar,
    this.codigoBarras,
    this.inventoryUnitId,
    this.initialStockQuantity,
    this.existingInventoryItemId,
    this.recipeComponents = const [],
  });

  final String? nombre;
  final String precioVenta;
  final String? costoEstandar;

  /// Código de barras capturado; vacío significa variante sin código.
  final String? codigoBarras;
  final String? inventoryUnitId;
  final String? initialStockQuantity;

  /// Recurso de inventario existente que se quiere recuperar para esta variante.
  ///
  /// Es la única forma de resolver un legado ambiguo: la persona usuaria elige
  /// explícitamente entre candidatos compatibles. No crea un CRUD de recursos ni
  /// reemplaza al resolver por memoria; el command valida el identificador y lo
  /// somete a las mismas reglas que la memoria.
  final String? existingInventoryItemId;
  final List<CrearArticuloRecipeComponentCommand> recipeComponents;
}
