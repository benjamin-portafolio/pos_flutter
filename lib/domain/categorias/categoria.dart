import 'color_categoria.dart';

class Categoria {
  const Categoria({
    required this.id,
    required this.nombre,
    required this.color,
    required this.orden,
  });

  final String id;
  final String nombre;
  final ColorCategoria color;
  final int? orden;
}
