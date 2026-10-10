import '../payloads/producto_proveedor_precio.dart';

/// Capacidad local de la proyección de producto para reemplazar hijos conocidos.
abstract interface class ProductoProveedoresProjectionStore {
  Future<void> replaceVariantSuppliers(
    String variantId,
    List<ProductoProveedorPrecio> suppliers,
  );
}
