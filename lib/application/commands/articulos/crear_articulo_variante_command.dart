import 'crear_articulo_recipe_component_command.dart';

class CrearArticuloVarianteCommand {
  const CrearArticuloVarianteCommand({
    required this.nombre,
    required this.precioVenta,
    required this.costoEstandar,
    this.inventoryUnitId,
    this.initialStockQuantity,
    this.recipeComponents = const [],
  });

  final String? nombre;
  final String precioVenta;
  final String? costoEstandar;
  final String? inventoryUnitId;
  final String? initialStockQuantity;
  final List<CrearArticuloRecipeComponentCommand> recipeComponents;
}
