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
    required this.variantePredeterminadaId,
    required this.precioPredeterminadoMenor,
    required this.variantesActivas,
  });

  final String productoId;
  final String nombre;
  final bool activo;
  final String? categoriaId;
  final String? categoriaNombre;
  final ColorCategoria? categoriaColor;
  final String variantePredeterminadaId;
  final int precioPredeterminadoMenor;
  final List<VarianteListado> variantesActivas;
}
