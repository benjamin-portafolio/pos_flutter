/// Resultado publicado solo cuando la transacción del lote ha terminado.
class ProductoImportLoteResult {
  const ProductoImportLoteResult({
    required this.creados,
    required this.actualizados,
    required this.sinCambios,
  });

  final int creados;
  final int actualizados;
  final int sinCambios;
}
