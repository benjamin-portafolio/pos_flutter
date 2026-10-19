import '../../../../domain/articulos/articulo_listado.dart';
import '../../../../domain/articulos/variante_listado.dart';
import '../../../../domain/inventario/recurso_inventario_listado.dart';
import '../../../../domain/inventario/minimum_stock_policy.dart';

/// Una variante con seguimiento directo, en el orden entregado por el catálogo.
class RemainingStockItem {
  const RemainingStockItem({
    required this.productoId,
    required this.articleName,
    required this.variant,
    required this.inventory,
  });

  final String productoId;
  final String articleName;
  final VarianteListado variant;
  final RecursoInventarioListado inventory;

  int? get minimumStockAtomic => variant.minimumStockAtomic;

  bool get isLow => const MinimumStockPolicy().isLow(
    minimumStockAtomic: minimumStockAtomic,
    quantityOnHandAtomic: inventory.existenciaAtomica,
    // fromArticles admite únicamente productos y variantes activos.
    productActive: true,
    variantActive: true,
    hasDirectTracking: variant.inventario != null,
    inventoryItemActive:
        inventory.activo && inventory.unidadPredeterminada.activa,
  );

  static List<RemainingStockItem> fromArticles(
    List<ArticuloListado> articles,
  ) => [
    for (final article in articles)
      if (article.activo)
        // El repositorio entrega únicamente variantes activas. Las recetas
        // sin vínculo directo tienen inventario null y quedan fuera.
        for (final variant in article.variantesActivas)
          if (variant.inventario case final inventory?)
            RemainingStockItem(
              productoId: article.productoId,
              articleName: article.nombre,
              variant: variant,
              inventory: inventory,
            ),
  ];
}
