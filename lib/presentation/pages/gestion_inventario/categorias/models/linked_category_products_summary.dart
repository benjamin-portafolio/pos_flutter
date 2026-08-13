import '../../../../../domain/articulos/articulo_vinculado_categoria.dart';

class LinkedCategoryProductsSummary {
  LinkedCategoryProductsSummary(Iterable<ArticuloVinculadoCategoria> products)
    : products = List.unmodifiable(products);

  final List<ArticuloVinculadoCategoria> products;

  int get total => products.length;
  int get activos => products.where((product) => product.activo).length;
  int get inactivos => products.where((product) => !product.activo).length;

  List<String> get productIds => List.unmodifiable(
    products.map((product) => product.productoId).toList()..sort(),
  );
}
