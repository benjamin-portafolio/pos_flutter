import 'package:drift/drift.dart';
import '../../../application/sync/projections/cliente_projection.dart';
import '../../../application/sync/projections/cliente_projection_store.dart';
import 'app_database.dart';

class DriftClienteProjectionStore implements ClienteProjectionStore {
  DriftClienteProjectionStore(this._dao);
  final ClienteDao _dao;
  @override
  Future<ClienteProjection?> findById(String id) async {
    final row = await _dao.findById(id);
    if (row == null) return null;
    return ClienteProjection(
      id: row.id,
      nombre: row.nombre,
      telefono: row.telefono,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }

  @override
  Future<void> insert(ClienteProjection p) => _dao.insertCliente(
    ClientesCompanion.insert(
      id: p.id,
      nombre: p.nombre,
      telefono: Value(p.telefono),
      active: Value(p.active),
      version: Value(p.version),
      createdEventId: Value(p.createdEventId),
      lastEventId: Value(p.lastEventId),
      lastServerSequence: Value(p.lastServerSequence),
    ),
  );
  @override
  Future<void> advanceServerSequence(
    String id,
    String eventId,
    int serverSequence,
  ) => _dao.advanceServerSequence(id, eventId, serverSequence);
  @override
  Future<void> deleteCreatedByEvent(String eventId) =>
      _dao.deleteCreatedByEvent(eventId);
}
