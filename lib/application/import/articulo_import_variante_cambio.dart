import '../edicion_masiva/cambio_explicito.dart';

/// Valores editables de una variante identificada. No admite inventario ni orden.
class ArticuloImportVarianteCambio {
  const ArticuloImportVarianteCambio({
    required this.id,
    required this.linea,
    this.offerPrice = const CambioExplicito.conservar(),
    required this.precioVentaMinor,
    this.nombre,
    this.precioCosteMinor,
    this.codigoBarras,
  });
  final String id;
  final int linea;
  final String? nombre;
  final int precioVentaMinor;
  final CambioExplicito<int?> offerPrice;
  final int? precioCosteMinor;
  final String? codigoBarras;
}
