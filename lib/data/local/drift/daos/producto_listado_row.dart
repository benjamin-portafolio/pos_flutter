part of '../app_database.dart';

/// Lectura conjunta del artículo, sus variantes y sus unidades y saldos locales.
class ProductoListadoRow {
  const ProductoListadoRow({
    required this.producto,
    required this.categoria,
    required this.variante,
    required this.unidadVenta,
    required this.inventario,
    required this.saldo,
    required this.unidadInventario,
  });

  final ProductRow producto;
  final CategoryRow? categoria;
  final ProductVariantRow? variante;
  final UnitRow? unidadVenta;
  final InventoryItemRow? inventario;
  final InventoryBalanceRow? saldo;
  final UnitRow? unidadInventario;
}
