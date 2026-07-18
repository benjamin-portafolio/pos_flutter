part of '../app_database.dart';

@DriftAccessor(tables: [Categories])
class CategoriaDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriaDaoMixin {
  CategoriaDao(super.db);

  Future<List<CategoryRow>> obtenerCategorias() {
    return (select(categories)
          ..where((category) => category.active.equals(true))
          ..orderBy([
            (category) => OrderingTerm(expression: category.sortOrder),
            (category) => OrderingTerm(expression: category.name),
          ]))
        .get();
  }

  Stream<List<CategoryRow>> watchCategorias() {
    return (select(categories)
          ..where((category) => category.active.equals(true))
          ..orderBy([
            (category) => OrderingTerm(expression: category.sortOrder),
            (category) => OrderingTerm(expression: category.name),
          ]))
        .watch();
  }
}
