import '../categorias/color_categoria.dart';
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
  });
  final String productoId;
  final String nombre;
  final bool activo;
  final String? categoriaId;
  final String? categoriaNombre;
  final ColorCategoria? categoriaColor;
  final List<VarianteListado> variantesActivas;

  /// Extremos del precio entre variantes activas, independientes de su orden.
  int get precioMinimoMenor => variantesActivas
      .map((variante) => variante.precioVentaMenor)
      .reduce((left, right) => left < right ? left : right);

  int get precioMaximoMenor => variantesActivas
      .map((variante) => variante.precioVentaMenor)
      .reduce((left, right) => left > right ? left : right);
}
