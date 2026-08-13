import 'color_categoria.dart';

class Categoria {
  const Categoria({
    required this.id,
    required this.nombre,
    required this.color,
    required this.orden,
    this.activa = true,
  });

  final String id;
  final String nombre;
  final ColorCategoria color;
  final int orden;
  final bool activa;
}
