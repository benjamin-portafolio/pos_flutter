class EliminarCategoriaCommand {
  const EliminarCategoriaCommand({
    required this.categoriaId,
    this.resolucion = ResolucionProductosCategoria.none,
    this.categoriaDestinoId,
    this.productoIdsConfirmados = const <String>[],
  });

  final String categoriaId;
  final ResolucionProductosCategoria resolucion;
  final String? categoriaDestinoId;
  final List<String> productoIdsConfirmados;
}

enum ResolucionProductosCategoria { none, move, uncategorize }
