part of '../app_database.dart';

/// Lectura exacta de una variante activa y su producto activo, con unidad de venta.
class ProductoCodigoBarrasRow {
  const ProductoCodigoBarrasRow({
    required this.producto,
    required this.variante,
    required this.unidadVenta,
  });

  final ProductRow producto;
  final ProductVariantRow variante;
  final UnitRow? unidadVenta;
}
