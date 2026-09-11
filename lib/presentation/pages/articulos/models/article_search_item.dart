import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../../domain/articulos/articulo_listado.dart';
import '../../../../domain/articulos/variante_listado.dart';

/// Una variante visible en el buscador, junto con los datos de su producto.
class ArticleSearchItem {
  const ArticleSearchItem({required this.article, required this.variant});

  final ArticuloListado article;
  final VarianteListado variant;

  /// Todas las palabras deben coincidir en el producto o en esta variante.
  /// Conserva primero los productos más recientes y el orden de sus variantes.
  static List<ArticleSearchItem> search(
    List<ArticuloListado> articles,
    String query,
  ) {
    final words = _normalize(
      query,
    ).split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    final sorted = articles.where((article) => article.activo).toList()
      ..sort((left, right) {
        final leftDate = left.fechaCreacion;
        final rightDate = right.fechaCreacion;
        if (leftDate != rightDate) {
          if (leftDate == null) return 1;
          if (rightDate == null) return -1;
          final byDate = rightDate.compareTo(leftDate);
          if (byDate != 0) return byDate;
        }
        final byName = _normalize(
          left.nombre,
        ).compareTo(_normalize(right.nombre));
        return byName != 0
            ? byName
            : left.productoId.compareTo(right.productoId);
      });
    final results = <ArticleSearchItem>[];
    for (final article in sorted) {
      final productName = _normalize(article.nombre);
      final variants = [...article.variantesActivas]
        ..sort((left, right) {
          final byOrder = left.orden.compareTo(right.orden);
          return byOrder != 0
              ? byOrder
              : left.varianteId.compareTo(right.varianteId);
        });
      for (final variant in variants) {
        final variantName = _normalize(variant.nombre ?? '');
        if (words.every(
          (word) => productName.contains(word) || variantName.contains(word),
        )) {
          results.add(ArticleSearchItem(article: article, variant: variant));
        }
      }
    }
    return results;
  }

  static String _normalize(String value) => unorm.nfkc(value).toLowerCase();
}
