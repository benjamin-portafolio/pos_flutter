import '../../edicion_masiva/base_revision_masiva.dart';
import '../../edicion_masiva/cambio_variante_masiva.dart';

/// Intención comercial acotada por producto: identidad, base confirmada y
/// cambios explícitos de variantes.
///
/// Solo expresa venta, oferta, costo estándar y la pareja de proveedor solicitada.
/// `CambioVarianteMasiva.entrada` pertenece a la recepción (sesión 3) y este
/// comando la ignora: una fila con solo entrada no emite `producto_actualizado`.
class EditarArticuloComercialCommand {
  const EditarArticuloComercialCommand({
    required this.productId,
    required this.base,
    required this.cambios,
  });

  final String productId;

  /// Base observada que la persona usuaria confirmó; no se sustituye por la viva.
  final BaseRevisionMasiva base;
  final List<CambioVarianteMasiva> cambios;
}
