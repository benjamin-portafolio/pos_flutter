import '../../domain/categorias/color_categoria.dart';

class EditarCategoriaCommand {
  const EditarCategoriaCommand({
    required this.categoriaId,
    required this.nombre,
    required this.color,
  });

  final String categoriaId;
  final String nombre;
  final ColorCategoria color;
}
