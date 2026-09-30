import 'crear_articulo_recipe_component_command.dart';

class CrearArticuloVarianteCommand {
  const CrearArticuloVarianteCommand({
    required this.nombre,
    required this.precioVenta,
    required this.costoEstandar,
    this.codigoBarras,
    this.inventoryUnitId,
    this.initialStockQuantity,
    this.recipeComponents = const [],
  });

  final String? nombre;
  final String precioVenta;
  final String? costoEstandar;

  /// Código de barras capturado; vacío significa variante sin código.
  final String? codigoBarras;
  final String? inventoryUnitId;
  final String? initialStockQuantity;
  final List<CrearArticuloRecipeComponentCommand> recipeComponents;
}
