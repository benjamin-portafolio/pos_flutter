import '../../../../../domain/articulos/articulo_detalle.dart';
import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../../domain/inventario/recurso_inventario_listado.dart';
import 'articulo_form_result.dart';
import 'recipe_component_form_result.dart';

/// Adapta el detalle persistido al formulario sin crear intenciones de escritura.
class ArticuloPreviewForm {
  static ArticuloFormResult fromDetalle(
    ArticuloDetalle detalle,
    List<RecursoInventarioListado> recursos,
  ) {
    final byId = {for (final recurso in recursos) recurso.id: recurso};
    RecursoInventarioListado resource(String id) {
      final value = byId[id];
      if (value == null) throw StateError('No se encontró el recurso $id.');
      return value;
    }

    String money(int value) =>
        '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
    return ArticuloFormResult(
      nombre: detalle.nombre,
      categoriaId: detalle.categoriaId,
      saleConfiguration: detalle.saleConfiguration,
      variantes: detalle.variantes
          .map(
            (variant) => ArticuloFormVarianteResult(
              id: variant.id,
              nombre: variant.nombre,
              precioVenta: money(variant.precioVentaMenor),
              costoEstandar: variant.costoEstandarMenor == null
                  ? null
                  : money(variant.costoEstandarMenor!),
              inventoryUnitId: variant.inventoryItemId == null
                  ? null
                  : resource(variant.inventoryItemId!).unidadPredeterminada.id,
              recipeComponents: variant.componentesReceta.entries
                  .map((entry) {
                    final recurso = resource(entry.key);
                    return RecipeComponentFormResult(
                      resource: recurso,
                      quantity: const InventoryQuantityCodec().formatAtomic(
                        entry.value,
                        recurso.unidadPredeterminada,
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }
}
