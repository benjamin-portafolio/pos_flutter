/// Un lote revertido por completo, con las líneas originales para corregirlo.
class ArticuloImportLoteFallido {
  const ArticuloImportLoteFallido({
    required this.numero,
    required this.productos,
    required this.lineas,
    required this.motivo,
  });

  final int numero;
  final List<String> productos;
  final List<int> lineas;
  final String motivo;
}
