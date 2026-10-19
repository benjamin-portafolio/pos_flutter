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
    required this.venta,
    required this.costo,
    required this.precioProveedor,
    required this.entrada,
  });

  final ClaveVariante clave;
  final BaseRevisionMasiva baseProducto;
  final CambioExplicito<int> venta;
  final CambioExplicito<int> costo;

  /// Null conserva todas las parejas; un valor modifica solo esta pareja.
  final ProveedorVariante? precioProveedor;
  final EntradaMercanciaMasiva? entrada;

  bool get tieneCambios =>
      venta.establecer ||
      costo.establecer ||
      precioProveedor != null ||
      entrada != null;
}
