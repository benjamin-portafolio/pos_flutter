/// Grupo con filas excluidas del archivo. Una actualización se excluye entera;
/// un alta conserva la política de importar sus filas válidas.
class ArticuloImportProductoError {
  const ArticuloImportProductoError({
    required this.nombre,
    required this.lineas,
    this.productId,
  });

  final String nombre;
  final String? productId;
  final List<int> lineas;
}
