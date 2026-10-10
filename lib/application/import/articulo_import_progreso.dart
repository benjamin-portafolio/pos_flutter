import 'articulo_import_lote_fallido.dart';

/// Foto del avance, publicada únicamente después de confirmar o revertir un lote.
class ArticuloImportProgreso {
  const ArticuloImportProgreso({
    required this.lotesTotales,
    required this.productosTotales,
    this.lotesProcesados = 0,
    this.productosImportados = 0,
    this.productosFallidos = 0,
    this.lotesFallidos = const [],
  });

  final int lotesTotales;
  final int productosTotales;
  final int lotesProcesados;
  final int productosImportados;
  final int productosFallidos;
  final List<ArticuloImportLoteFallido> lotesFallidos;

  bool get terminado => lotesProcesados == lotesTotales;
}
