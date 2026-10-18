import 'articulo_import_lote_fallido.dart';

/// Foto inicial y avance publicado tras confirmar o revertir cada lote.
class ArticuloImportProgreso {
  const ArticuloImportProgreso({
    required this.lotesTotales,
    required this.productosTotales,
    this.lotesProcesados = 0,
    this.productosImportados = 0,
    this.productosCreados = 0,
    this.productosActualizados = 0,
    this.productosOmitidos = 0,
    this.productosFallidos = 0,
    this.lotesFallidos = const [],
  });

  final int lotesTotales;

  /// Productos ejecutables confirmados; las omisiones iniciales no consumen lote.
  final int productosTotales;
  final int lotesProcesados;
  final int productosImportados;
  final int productosCreados;
  final int productosActualizados;

  /// Incluye omisiones de preparación y no-ops detectados al guardar.
  final int productosOmitidos;
  final int productosFallidos;
  final List<ArticuloImportLoteFallido> lotesFallidos;

  bool get terminado => lotesProcesados == lotesTotales;
}
