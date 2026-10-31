import '../../edicion_masiva/cambio_explicito.dart';

/// Valores comerciales completos de una variante incluida en el CSV.
/// Costo/barcode vacíos retiran; oferta usa intención explícita y conserva
/// por defecto, incluidos los archivos que desconocen el campo.
class ActualizarArticuloVarianteCsvCommand {
  const ActualizarArticuloVarianteCsvCommand({
    required this.variantId,
    required this.nombre,
    this.offerPrice = const CambioExplicito.conservar(),
    required this.precioVentaMinor,
    required this.precioCosteMinor,
    required this.codigoBarras,
  });

  final String variantId;
  final String? nombre;
  final int precioVentaMinor;
  final CambioExplicito<int?> offerPrice;
  final int? precioCosteMinor;
  final String? codigoBarras;
}
