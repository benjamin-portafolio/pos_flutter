import '../../domain/categorias/color_categoria.dart';

class CrearCategoriaCommand {
  const CrearCategoriaCommand({required this.nombre, required this.color});

  final String nombre;
  final ColorCategoria color;
}
