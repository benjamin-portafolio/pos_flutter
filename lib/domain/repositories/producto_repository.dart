import '../articulos/articulo_listado.dart';
import '../articulos/articulo_vinculado_categoria.dart';

abstract interface class ProductoRepository {
  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  );

  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  });
}
