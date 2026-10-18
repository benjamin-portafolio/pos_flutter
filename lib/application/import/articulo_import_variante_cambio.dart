/// Valores editables de una variante identificada. No admite inventario ni orden.
class ArticuloImportVarianteCambio {
  const ArticuloImportVarianteCambio({
    required this.id,
    required this.linea,
    required this.precioVentaMinor,
    this.nombre,
    this.precioCosteMinor,
    this.codigoBarras,
  });
  final String id;
  final int linea;
  final String? nombre;
  final int precioVentaMinor;
  final int? precioCosteMinor;
  final String? codigoBarras;
}
