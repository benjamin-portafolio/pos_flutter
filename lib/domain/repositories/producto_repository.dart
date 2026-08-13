import '../articulos/articulo_listado.dart';

abstract interface class ProductoRepository {
  Future<int> contarArticulosPorCategoria(String categoriaId);

  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  });
}
