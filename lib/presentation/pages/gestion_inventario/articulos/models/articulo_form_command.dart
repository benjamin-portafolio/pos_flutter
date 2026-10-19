import '../../../../../application/commands/articulos/crear_articulo_command.dart';
import '../../../../../application/commands/articulos/crear_articulo_recipe_component_command.dart';
import '../../../../../application/commands/articulos/crear_articulo_variante_command.dart';
import 'articulo_form_result.dart';

/// Traduce la captura de presentación a la intención del agregado completo.
extension ArticuloFormCommand on ArticuloFormResult {
  CrearArticuloCommand toCommand() => CrearArticuloCommand.conVariantes(
    nombre: nombre,
    categoriaId: categoriaId,
    variantes: variantes
        .map(
          (variant) => CrearArticuloVarianteCommand.conProveedores(
            nombre: variant.nombre,
            precioVenta: variant.precioVenta,
            costoEstandar: variant.costoEstandar,
            codigoBarras: variant.codigoBarras,
            proveedores: variant.proveedores,
            inventoryUnitId: variant.inventoryUnitId,
            initialStockQuantity: variant.existenciaInicial,
            minimumStock: variant.minimumStock,
            recipeComponents: variant.recipeComponents
                .map(
                  (component) => CrearArticuloRecipeComponentCommand(
                    inventoryItemId: component.resource.id,
                    quantity: component.quantity,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
    saleConfiguration: saleConfiguration,
  );
}
