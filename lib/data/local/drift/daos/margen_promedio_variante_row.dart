part of '../app_database.dart';

/// Fila mínima para calcular el margen de una variante activa de un producto
/// activo dentro de una categoría o proveedor.
class MargenPromedioVarianteRow {
  const MargenPromedioVarianteRow({
    required this.grupoId,
    required this.productoId,
    required this.precioVentaMenor,
    required this.costoEstandarMenor,
  });

  /// Categoría o proveedor al que pertenece esta fila.
  final String grupoId;

  /// Producto propietario de la variante; evita contarlo dos veces al agrupar.
  final String productoId;

  /// Precio de venta de la variante en unidad monetaria menor.
  final int precioVentaMenor;

  /// Costo estándar de la variante; `null` significa desconocido.
  final int? costoEstandarMenor;
}
