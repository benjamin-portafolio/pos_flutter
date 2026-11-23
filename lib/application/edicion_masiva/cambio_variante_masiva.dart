import '../sync/payloads/supplier_replenishment_patch.dart';
import '../../domain/articulos/proveedor_variante.dart';
import 'base_revision_masiva.dart';
import 'cambio_explicito.dart';
import 'clave_variante.dart';
import 'entrada_mercancia_masiva.dart';

/// Intención normalizada; no es un formulario ni ejecuta escrituras.
class CambioVarianteMasiva {
  const CambioVarianteMasiva({
    required this.clave,
    required this.baseProducto,
    this.targetInventoryItemId,
    this.targetUnitId,
    this.replenishment = const SupplierReplenishmentPatch.preserve(),
    this.oferta = const CambioExplicito.conservar(),
    required this.venta,
    required this.costo,
    required this.precioProveedor,
    required this.entrada,
  });

  final String? targetInventoryItemId;
  final String? targetUnitId;
  final SupplierReplenishmentPatch replenishment;
  final ClaveVariante clave;
  final BaseRevisionMasiva baseProducto;
  final CambioExplicito<int> venta;
  final CambioExplicito<int?> oferta;
  final CambioExplicito<int> costo;

  /// Null no solicita una cotización explícita; un valor modifica esta pareja.
  /// Cambiar el costo actualiza además el precio del proveedor principal.
  final ProveedorVariante? precioProveedor;
  final EntradaMercanciaMasiva? entrada;

  bool get tieneCambios =>
      replenishment.hasSupplier ||
      replenishment.hasTarget ||
      oferta.establecer ||
      venta.establecer ||
      costo.establecer ||
      precioProveedor != null ||
      entrada != null;
}
