/// Valores comerciales completos de una variante incluida en el CSV.
/// Los opcionales vacíos retiran el valor; no significan conservarlo.
class ActualizarArticuloVarianteCsvCommand {
  const ActualizarArticuloVarianteCsvCommand({
    required this.variantId,
    required this.nombre,
    required this.precioVentaMinor,
    required this.precioCosteMinor,
    required this.codigoBarras,
  });

  final String variantId;
  final String? nombre;
  final int precioVentaMinor;
  final int? precioCosteMinor;
  final String? codigoBarras;
}
