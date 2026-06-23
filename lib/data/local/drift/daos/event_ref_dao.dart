part of '../app_database.dart';

/// Data Access Object for performing database operations on the EventRefs table.
@DriftAccessor(tables: [EventRefs])
class EventRefDao extends DatabaseAccessor<AppDatabase>
    with _$EventRefDaoMixin {
  EventRefDao(super.db);

  /// Inserta múltiples referencias de evento.
  Future<void> insertarReferencias(List<EventRefsCompanion> entities) async {
    await batch((batch) {
      batch.insertAll(eventRefs, entities);
    });
  }

  /// Obtiene referencias de eventos pendientes de sincronización local.
  Future<List<EventRef>> obtenerReferenciasLocalesPendientes() {
    return (select(
      eventRefs,
    )..where((t) => t.source.equals('local_pending'))).get();
  }

  /// Actualiza el estado y secuencia de servidor para referencias de un evento.
  Future<int> actualizarReferenciasSincronizadas(
    String eventId,
    int serverSequence,
  ) {
    return (update(eventRefs)..where((t) => t.eventId.equals(eventId))).write(
      EventRefsCompanion(
        source: const Value('server'),
        serverSequence: Value(serverSequence),
      ),
    );
  }
}
