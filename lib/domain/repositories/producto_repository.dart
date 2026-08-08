import '../articulos/articulo_listado.dart';

abstract interface class ProductoRepository {
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  });
}
