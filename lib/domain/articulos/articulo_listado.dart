import '../categorias/color_categoria.dart';
import '../inventario/unidad_inventario.dart';
import 'variante_listado.dart';

class ArticuloListado {
  const ArticuloListado({
    required this.productoId,
    required this.nombre,
    required this.activo,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.categoriaColor,
    required this.variantesActivas,
    this.unidadVenta,
    this.cantidadReferenciaPrecioAtomica,
    this.fechaCreacion,
  });
  final String productoId;
  final String nombre;
  final bool activo;
  final String? categoriaId;
  final String? categoriaNombre;
  final ColorCategoria? categoriaColor;
  final List<VarianteListado> variantesActivas;

  /// Fecha original del evento de creación; null si no se conserva ese evento.
  final DateTime? fechaCreacion;

  /// Unidad de venta por fracción; null para artículos vendidos por pieza.
  final UnidadInventario? unidadVenta;

  /// Cantidad en átomos a la que corresponde el precio en [unidadVenta].
  final int? cantidadReferenciaPrecioAtomica;
}
