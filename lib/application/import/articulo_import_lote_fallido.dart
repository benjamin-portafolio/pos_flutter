/// Un lote revertido por completo, con las líneas originales para corregirlo.
class ArticuloImportLoteFallido {
  const ArticuloImportLoteFallido({
    required this.numero,
    required this.productos,
    required this.lineas,
    required this.motivo,
    this.productIds = const [],
  });

  final int numero;
  final List<String> productos;
  final List<int> lineas;
  final String motivo;

  /// Identidades de las actualizaciones revertidas; las altas aún no tienen ID.
  final List<String> productIds;
}
