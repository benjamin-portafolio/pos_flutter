/// Resultado publicado solo cuando la transacción del lote ha terminado.
class ProductoImportLoteResult {
  const ProductoImportLoteResult({
    required this.creados,
    this.eliminados = 0,
    required this.actualizados,
    required this.sinCambios,
  });

  final int creados;
  final int eliminados;
  final int actualizados;
  final int sinCambios;
}
