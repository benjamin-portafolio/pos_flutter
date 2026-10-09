import 'proveedor_variante.dart';

class VarianteDetalle {
  VarianteDetalle({
    this.id,
    required this.nombre,
    required this.precioVentaMenor,
    required this.costoEstandarMenor,
    required this.inventoryItemId,
    required this.componentesReceta,
    this.codigoBarras,
    List<ProveedorVariante>? proveedores,
  }) : proveedores = ProveedorVariante.canonical(proveedores);
  final List<ProveedorVariante>? proveedores;
  final String? id;
  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final String? inventoryItemId;

  /// Código de barras opcional, solo dígitos, conservado como texto.
  final String? codigoBarras;

  /// Consumo atómico por identificador del recurso de inventario.
  final Map<String, int> componentesReceta;
}
