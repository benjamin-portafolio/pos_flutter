import '../../../../../domain/articulos/proveedor_variante.dart';

/// Resultado inmutable del selector; no realiza escrituras.
class ProveedorPreciosFormResult {
  ProveedorPreciosFormResult(List<ProveedorVariante> proveedores)
    : proveedores = ProveedorVariante.canonical(proveedores)!;

  final List<ProveedorVariante> proveedores;
}
