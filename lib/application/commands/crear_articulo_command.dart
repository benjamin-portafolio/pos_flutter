import '../../domain/articulos/sale_configuration.dart';

class CrearArticuloCommand {
  const CrearArticuloCommand({
    required this.nombre,
    required this.precioVenta,
    this.categoriaId,
    this.saleConfiguration = const UnitSaleConfiguration(),
  }) : variantes = const [];

  const CrearArticuloCommand.conVariantes({
    required this.nombre,
    required this.variantes,
    this.categoriaId,
    this.saleConfiguration = const UnitSaleConfiguration(),
  }) : precioVenta = null;

  final String nombre;
  final String? categoriaId;
  final String? precioVenta;
  final List<CrearArticuloVarianteCommand> variantes;
  final SaleConfiguration saleConfiguration;
}

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

class CrearArticuloRecipeComponentCommand {
  const CrearArticuloRecipeComponentCommand({
    required this.inventoryItemId,
    required this.quantity,
  });

  final String inventoryItemId;
  final String quantity;
}
