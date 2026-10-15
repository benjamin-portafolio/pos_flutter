/// Asigna o reemplaza el código de una variante sobre la base confirmada.
class AsignarCodigoBarrasVarianteCommand {
  const AsignarCodigoBarrasVarianteCommand({
    required this.productId,
    required this.variantId,
    required this.baseEventId,
    required this.codigoBarras,
  });

  final String productId;
  final String variantId;
  final String baseEventId;
  final String codigoBarras;
}
