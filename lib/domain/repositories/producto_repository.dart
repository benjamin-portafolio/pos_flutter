import '../articulos/articulo_listado.dart';
import '../articulos/articulo_detalle.dart';
import '../articulos/articulo_vinculado_categoria.dart';

abstract interface class ProductoRepository {
  Future<ArticuloDetalle?> obtenerDetalle(String productoId);

  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  );

  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  });

  /// Variantes activas de productos activos. Emite el conteo cada vez que el
  /// catálogo cambia, para badges que solo necesitan el total.
  Stream<int> watchVariantesActivasCount();
}
