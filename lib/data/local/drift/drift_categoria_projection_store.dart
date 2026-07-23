import 'package:drift/drift.dart';

import '../../../application/sync/projections/categoria_projection_store.dart';
import '../../../domain/categorias/color_categoria.dart';
import 'app_database.dart' as drift;

class DriftCategoriaProjectionStore implements CategoriaProjectionStore {
  DriftCategoriaProjectionStore({required drift.CategoriaDao categoriaDao})
    : _categoriaDao = categoriaDao;

  final drift.CategoriaDao _categoriaDao;

  @override
  Future<CategoriaProjection?> findById(String id) async {
    final row = await _categoriaDao.obtenerCategoriaPorId(id);
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<void> insert(CategoriaProjection projection) async {
    await _categoriaDao.insertarCategoria(
      drift.CategoriesCompanion.insert(
        id: projection.id,
        name: projection.nombre,
        colorKey: Value(projection.color.key),
        sortOrder: Value(projection.orden),
        active: Value(projection.active),
        version: Value(projection.version),
        createdEventId: Value(projection.createdEventId),
        lastEventId: Value(projection.lastEventId),
        lastServerSequence: Value(projection.lastServerSequence),
      ),
    );
  }

  @override
  Future<void> update(CategoriaProjection projection) async {
    await _categoriaDao.actualizarCategoria(
      projection.id,
      drift.CategoriesCompanion(
        name: Value(projection.nombre),
        colorKey: Value(projection.color.key),
        sortOrder: Value(projection.orden),
        active: Value(projection.active),
        version: Value(projection.version),
        createdEventId: Value(projection.createdEventId),
        lastEventId: Value(projection.lastEventId),
        lastServerSequence: Value(projection.lastServerSequence),
      ),
    );
  }

  @override
  Future<void> updateSyncMetadata(
    String id, {
    required String eventId,
    int? serverSequence,
  }) async {
    await _categoriaDao.actualizarMetadataSincronizacion(
      id,
      eventId: eventId,
      serverSequence: serverSequence,
    );
  }

  @override
  Future<void> deleteById(String id) async {
    await _categoriaDao.eliminarCategoriaPorId(id);
  }

  @override
  Future<void> deleteCreatedByEvent(String eventId) async {
    await _categoriaDao.eliminarCategoriaCreadaPorEvento(eventId);
  }

  CategoriaProjection _fromRow(drift.CategoryRow row) {
    return CategoriaProjection(
      id: row.id,
      nombre: row.name,
      color: ColorCategoria.fromKey(row.colorKey),
      orden: row.sortOrder,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }
}
