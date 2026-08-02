import '../../domain/categorias/direccion_movimiento_categoria.dart';

class MoverCategoriaCommand {
  const MoverCategoriaCommand({
    required this.categoriaId,
    required this.direccion,
  });

  final String categoriaId;
  final DireccionMovimientoCategoria direccion;
}
