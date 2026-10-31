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
    this.offerPriceMinor,
    this.minimumStockAtomic,
    this.knowsMinimumStock = false,
    List<ProveedorVariante>? proveedores,
  }) : proveedores = ProveedorVariante.canonical(proveedores);
  final List<ProveedorVariante>? proveedores;
  final String? id;
  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;

  /// Oferta opcional, independiente del costo y del precio normal.
  final int? offerPriceMinor;

  /// Umbral atómico y conocimiento del contrato, independiente de SQL null.
  final int? minimumStockAtomic;
  final bool knowsMinimumStock;
  final String? inventoryItemId;

  /// Código de barras opcional, solo dígitos, conservado como texto.
  final String? codigoBarras;

  /// Consumo atómico por identificador del recurso de inventario.
  final Map<String, int> componentesReceta;
}
