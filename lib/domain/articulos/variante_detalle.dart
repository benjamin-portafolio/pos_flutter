class VarianteDetalle {
  const VarianteDetalle({
    this.id,
    required this.nombre,
    required this.precioVentaMenor,
    required this.costoEstandarMenor,
    required this.inventoryItemId,
    required this.componentesReceta,
    this.codigoBarras,
  });
  final String? id;
  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final String? inventoryItemId;

  /// Código de barras opcional, solo dígitos, conservado como texto.
  final String? codigoBarras;

  /// Consumo atómico por identificador del recurso de inventario.
  final Map<String, int> componentesReceta;
}
