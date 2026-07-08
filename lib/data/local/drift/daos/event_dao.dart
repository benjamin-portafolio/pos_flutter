part of '../app_database.dart';

/// Data Access Object for performing database operations on the Events table.
@DriftAccessor(tables: [Events])
class EventDao extends DatabaseAccessor<AppDatabase> with _$EventDaoMixin {
  EventDao(super.db);

  /// Inserta un nuevo evento en la bitácora.
  Future<int> insertarEvento(EventsCompanion entity) {
    return into(events).insert(entity);
  }

  /// Obtiene todos los eventos con estado pendiente de sincronización.
  Future<List<EventRecord>> obtenerEventosPendientes() {
    return (select(events)
          ..where((t) => t.syncStatus.equals('pending'))
          ..orderBy([(t) => OrderingTerm(expression: t.localSequence)]))
        .get();
  }

  /// Obtiene conflictos locales que aun no tienen secuencia del servidor.
  Future<List<EventRecord>> obtenerConflictosNoReportados() {
    return (select(events)
          ..where(
            (t) => t.syncStatus.equals('conflict') & t.serverSequence.isNull(),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.localSequence)]))
        .get();
  }

  /// Observa la cola local de eventos pendientes de sincronización.
  Stream<List<EventRecord>> watchEventosPendientes() {
    return (select(events)
          ..where((t) => t.syncStatus.equals('pending'))
          ..orderBy([(t) => OrderingTerm(expression: t.localSequence)]))
        .watch();
  }

  /// Actualiza el estado de sincronización de un evento específico.
  Future<int> actualizarEstadoSincronizacion(
    String eventId,
    String status, {
    int? serverSequence,
    DateTime? serverTime,
    String? rejectionReason,
  }) {
    final companion = EventsCompanion(
      syncStatus: Value(status),
      serverSequence: Value(serverSequence),
      createdAtServer: Value(serverTime),
      rejectionReason: rejectionReason == null
          ? const Value.absent()
          : Value(rejectionReason),
    );

    return (update(
      events,
    )..where((t) => t.eventId.equals(eventId))).write(companion);
  }
}
