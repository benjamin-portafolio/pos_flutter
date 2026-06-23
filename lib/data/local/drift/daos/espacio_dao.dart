part of '../app_database.dart';

/// Data Access Object for performing database operations on the Espacios table.
@DriftAccessor(tables: [Espacios])
class EspacioDao extends DatabaseAccessor<AppDatabase> with _$EspacioDaoMixin {
  EspacioDao(super.db);

  /// Obtiene la lista completa de espacios activos.
  Future<List<Espacio>> obtenerEspacios() {
    return (select(espacios)
          ..where((t) => t.active.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.nombre)]))
        .get();
  }

  /// Stream reactivo para observar en tiempo real la lista de espacios activos.
  Stream<List<Espacio>> watchEspacios() {
    return (select(espacios)
          ..where((t) => t.active.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.nombre)]))
        .watch();
  }

  Future<Espacio?> obtenerEspacioPorId(String id) {
    return (select(espacios)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Inserta un nuevo espacio en la base de datos.
  Future<int> insertarEspacio(EspaciosCompanion entity) {
    return into(espacios).insert(entity);
  }

  Future<int> upsertEspacio(EspaciosCompanion entity) {
    return into(espacios).insertOnConflictUpdate(entity);
  }

  /// Actualiza un espacio existente.
  Future<bool> actualizarEspacio(Espacio entity) {
    return update(espacios).replace(entity);
  }
}
