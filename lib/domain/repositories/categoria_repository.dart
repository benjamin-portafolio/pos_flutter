import '../categorias/categoria.dart';

abstract class CategoriaRepository {
  Stream<List<Categoria>> watchCategorias();

  Future<List<Categoria>> obtenerCategorias();
}
