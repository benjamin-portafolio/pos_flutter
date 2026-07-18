import '../../domain/categorias/categoria.dart';
import '../../domain/categorias/color_categoria.dart';
import '../../domain/repositories/categoria_repository.dart';
import '../local/drift/app_database.dart' as drift;

class CategoriaRepositoryImpl implements CategoriaRepository {
  CategoriaRepositoryImpl({required drift.CategoriaDao categoriaDao})
    : _categoriaDao = categoriaDao;

  final drift.CategoriaDao _categoriaDao;

  @override
  Future<List<Categoria>> obtenerCategorias() async {
    final rows = await _categoriaDao.obtenerCategorias();
    return rows.map(_toDomain).toList();
  }

  @override
  Stream<List<Categoria>> watchCategorias() {
    return _categoriaDao.watchCategorias().map(
      (rows) => rows.map(_toDomain).toList(),
    );
  }

  Categoria _toDomain(drift.CategoryRow row) {
    return Categoria(
      id: row.id,
      nombre: row.name,
      color: ColorCategoria.fromKey(row.colorKey),
      orden: row.sortOrder,
    );
  }
}
