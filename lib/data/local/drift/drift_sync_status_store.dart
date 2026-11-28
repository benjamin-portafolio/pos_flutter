import 'package:drift/drift.dart';
import '../../../application/sync/models/sync_local_status.dart';
import '../../../application/sync/models/sync_problem.dart';
import '../../../application/sync/sync_status_store.dart';
import 'app_database.dart';

class DriftSyncStatusStore implements SyncStatusStore {
  DriftSyncStatusStore(this._db);

  final AppDatabase _db;

  @override
  Stream<SyncLocalStatus> watch() {
    final query = _db.select(_db.events)
      ..where(
        (e) =>
            e.deliveryStatus.isIn(['pending', 'conflict', 'rejected']) |
            e.applicationStatus.equals('failed'),
      );
    return query.watch().map(
      (rows) => SyncLocalStatus(
        pending: rows.where((e) => e.deliveryStatus == 'pending').length,
        problems: List.unmodifiable(
          rows
              .where(
                (e) =>
                    e.deliveryStatus == 'conflict' ||
                    e.deliveryStatus == 'rejected' ||
                    e.applicationStatus == 'failed',
              )
              .map(
                (e) => SyncProblem(
                  eventId: e.eventId,
                  eventType: e.eventType,
                  reason:
                      e.rejectionReason ??
                      (e.applicationStatus == 'failed'
                          ? 'No se pudo aplicar el cambio en este dispositivo.'
                          : e.deliveryStatus == 'conflict'
                          ? 'El cambio tiene un conflicto con el servidor.'
                          : 'El servidor rechazó el cambio.'),
                ),
              ),
        ),
      ),
    );
  }
}
