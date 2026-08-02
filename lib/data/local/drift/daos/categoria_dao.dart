part of '../app_database.dart';

@DriftAccessor(tables: [Categories])
class CategoriaDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriaDaoMixin {
  CategoriaDao(super.db);

  Future<List<CategoryRow>> obtenerCategorias() {
    return (select(categories)..orderBy([
          (category) => OrderingTerm(expression: category.sortOrder),
          (category) => OrderingTerm(expression: category.name),
          (category) => OrderingTerm(expression: category.id),
        ]))
        .get();
  }

  Stream<List<CategoryRow>> watchCategorias() {
    return (select(categories)..orderBy([
          (category) => OrderingTerm(expression: category.sortOrder),
          (category) => OrderingTerm(expression: category.name),
          (category) => OrderingTerm(expression: category.id),
        ]))
        .watch();
  }

  Future<CategoryRow?> obtenerCategoriaPorId(String id) {
    return (select(
      categories,
    )..where((category) => category.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertarCategoria(CategoriesCompanion entity) {
    return into(categories).insert(entity);
  }

  Future<int> actualizarCategoria(String id, CategoriesCompanion entity) {
    return (update(
      categories,
    )..where((category) => category.id.equals(id))).write(entity);
  }

  Future<int> actualizarMetadataSincronizacion(
    String id, {
    required String eventId,
    int? serverSequence,
  }) {
    return (update(
      categories,
    )..where((category) => category.id.equals(id))).write(
      CategoriesCompanion(
        lastEventId: Value(eventId),
        lastServerSequence: serverSequence == null
            ? const Value.absent()
            : Value(serverSequence),
      ),
    );
  }

  Future<int> avanzarLastServerSequence(String id, int serverSequence) {
    return (update(categories)..where(
          (category) =>
              category.id.equals(id) &
              (category.lastServerSequence.isNull() |
                  category.lastServerSequence.isSmallerThanValue(
                    serverSequence,
                  )),
        ))
        .write(CategoriesCompanion(lastServerSequence: Value(serverSequence)));
  }

  Future<int> eliminarCategoriaPorId(String id) {
    return (delete(
      categories,
    )..where((category) => category.id.equals(id))).go();
  }

  Future<int> eliminarCategoriaCreadaPorEvento(String eventId) {
    return (delete(
      categories,
    )..where((category) => category.createdEventId.equals(eventId))).go();
  }
}
