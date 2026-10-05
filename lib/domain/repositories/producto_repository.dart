import '../articulos/articulo_listado.dart';
import '../articulos/articulo_detalle.dart';
import '../articulos/articulo_vinculado_categoria.dart';
import '../articulos/variante_por_codigo_barras.dart';

abstract interface class ProductoRepository {
  /// Coincidencias exactas normalizadas con CodigoBarras, conservando ceros.
  /// Vacío devuelve cero candidatos; una entrada incompatible lanza ArgumentError.
  /// Solo incluye productos y variantes activos; no presupone unicidad.
  Future<List<VariantePorCodigoBarras>> buscarVariantesPorCodigoBarras(
    String codigo,
  );

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
