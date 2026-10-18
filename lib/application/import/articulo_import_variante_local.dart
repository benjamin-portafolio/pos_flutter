/// Campos comparables y de identidad; no contiene saldos ni historial.
class ArticuloImportVarianteLocal {
  const ArticuloImportVarianteLocal({
    required this.id,
    required this.productId,
    required this.activa,
    required this.sortOrder,
    required this.precioVentaMinor,
    required this.seguimientoExistencias,
    this.nombre,
    this.precioCosteMinor,
    this.codigoBarras,
  });
  final String id;
  final String productId;
  final bool activa;
  final int sortOrder;
  final String? nombre;
  final int precioVentaMinor;
  final int? precioCosteMinor;
  final String? codigoBarras;
  final bool seguimientoExistencias;
}
