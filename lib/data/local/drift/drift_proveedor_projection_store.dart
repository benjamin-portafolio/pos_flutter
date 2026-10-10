import 'package:drift/drift.dart';
import '../../../application/sync/projections/proveedor_projection.dart';
import '../../../application/sync/projections/proveedor_projection_store.dart';
import 'app_database.dart';

class DriftProveedorProjectionStore implements ProveedorProjectionStore {
  DriftProveedorProjectionStore(this._dao);
  final ProveedorDao _dao;

  @override
  Future<T> atomic<T>(Future<T> Function() action) =>
      _dao.db.transaction(action);

  @override
  Future<ProveedorProjection?> findById(String id) async {
    final row = await _dao.findById(id);
    if (row == null) return null;
    return ProveedorProjection(
      id: row.id,
      name: row.name,
      phone: row.phone,
      notes: row.notes,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }

  @override
  Future<void> deleteCreatedByEvent(String eventId) async {
    final db = _dao.db;
    await (db.delete(
      db.suppliers,
    )..where((s) => s.createdEventId.equals(eventId))).go();
  }

  @override
  Future<void> advanceServerSequence(String id, int sequence) async {
    final current = await findById(id);
    if (current == null || (current.lastServerSequence ?? 0) >= sequence) {
      return;
    }
    await (_dao.db.update(_dao.db.suppliers)..where((s) => s.id.equals(id)))
        .write(SuppliersCompanion(lastServerSequence: Value(sequence)));
  }

  @override
  Future<void> save(ProveedorProjection p) => _dao.save(
    SuppliersCompanion.insert(
      id: p.id,
      name: p.name,
      phone: Value(p.phone),
      notes: Value(p.notes),
      active: Value(p.active),
      version: Value(p.version),
      createdEventId: Value(p.createdEventId),
      lastEventId: Value(p.lastEventId),
      lastServerSequence: Value(p.lastServerSequence),
    ),
  );
}
