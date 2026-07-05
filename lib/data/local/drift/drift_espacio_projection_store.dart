import 'package:drift/drift.dart';

import '../../../application/sync/projections/espacio_projection_store.dart';
import 'app_database.dart' as drift;

class DriftEspacioProjectionStore implements EspacioProjectionStore {
  DriftEspacioProjectionStore({required drift.EspacioDao espacioDao})
    : _espacioDao = espacioDao;

  final drift.EspacioDao _espacioDao;

  @override
  Future<EspacioProjection?> findById(String id) async {
    final row = await _espacioDao.obtenerEspacioPorId(id);
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<EspacioProjection?> findByIdentificacion(String identificacion) async {
    final row = await _espacioDao.obtenerEspacioPorIdentificacion(
      identificacion,
    );
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<void> insert(EspacioProjection projection) async {
    await _espacioDao.insertarEspacio(
      drift.EspaciosCompanion.insert(
        id: projection.id,
        nombre: projection.nombre,
        identificacion: Value(projection.identificacion),
        visibilidad: projection.visibilidad,
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
    await _espacioDao.actualizarMetadataSincronizacion(
      id,
      eventId: eventId,
      serverSequence: serverSequence,
    );
  }

  @override
  Future<void> deleteById(String id) async {
    await _espacioDao.eliminarEspacioPorId(id);
  }

  @override
  Future<void> deleteCreatedByEvent(String eventId) async {
    await _espacioDao.eliminarEspacioCreadoPorEvento(eventId);
  }

  EspacioProjection _fromRow(drift.Espacio row) {
    return EspacioProjection(
      id: row.id,
      nombre: row.nombre,
      identificacion: row.identificacion,
      visibilidad: row.visibilidad,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }
}
