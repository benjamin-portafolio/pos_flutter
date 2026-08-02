part of '../app_database.dart';

/// Data Access Object for performing database operations on the Events table.
@DriftAccessor(tables: [Events])
class EventDao extends DatabaseAccessor<AppDatabase> with _$EventDaoMixin {
  EventDao(super.db);

  /// Inserta un nuevo evento en la bitácora.
  Future<int> insertarEvento(EventsCompanion entity) {
    return into(events).insert(entity);
  }

  /// Obtiene todos los eventos con entrega remota pendiente.
  Future<List<EventRecord>> obtenerEventosPendientes() {
    return (select(events)
          ..where((t) => t.deliveryStatus.equals('pending'))
          ..orderBy([(t) => OrderingTerm(expression: t.localSequence)]))
        .get();
  }

  /// Obtiene un evento por su identificador para resolver dependencias locales.
  Future<EventRecord?> obtenerEventoPorId(String eventId) {
    return (select(
      events,
    )..where((event) => event.eventId.equals(eventId))).getSingleOrNull();
  }

  /// Obtiene eventos oficiales posteriores a una base para revalidar cambios
  /// pendientes del mismo agregado.
  Future<List<EventRecord>> obtenerEventosSincronizadosDelAgregadoDespuesDe({
    required String aggregateType,
    required String aggregateId,
    required int serverSequence,
  }) {
    return (select(events)
          ..where(
            (event) =>
                event.deliveryStatus.equals('delivered') &
                event.aggregateType.equals(aggregateType) &
                event.aggregateId.equals(aggregateId) &
                event.serverSequence.isBiggerThanValue(serverSequence),
          )
          ..orderBy([
            (event) => OrderingTerm(expression: event.serverSequence),
          ]))
        .get();
  }

  /// Obtiene eventos oficiales de un tipo posteriores a una base. Permite
  /// revalidar eventos que afectan mas de un agregado principal.
  Future<List<EventRecord>> obtenerEventosSincronizadosPorTipoDespuesDe({
    required String eventType,
    required int serverSequence,
  }) {
    return (select(events)
          ..where(
            (event) =>
                event.deliveryStatus.equals('delivered') &
                event.eventType.equals(eventType) &
                event.serverSequence.isBiggerThanValue(serverSequence),
          )
          ..orderBy([
            (event) => OrderingTerm(expression: event.serverSequence),
          ]))
        .get();
  }

  /// Obtiene conflictos locales que aun no tienen secuencia del servidor.
  Future<List<EventRecord>> obtenerConflictosNoReportados() {
    return (select(events)
          ..where(
            (t) =>
                t.deliveryStatus.equals('conflict') & t.serverSequence.isNull(),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.localSequence)]))
        .get();
  }

  /// Observa la cola local de eventos pendientes de entrega remota.
  Stream<List<EventRecord>> watchEventosPendientes() {
    return (select(events)
          ..where((t) => t.deliveryStatus.equals('pending'))
          ..orderBy([(t) => OrderingTerm(expression: t.localSequence)]))
        .watch();
  }

  /// Actualiza el estado de entrega remota de un evento específico.
  Future<int> actualizarEstadoSincronizacion(
    String eventId,
    String status, {
    int? serverSequence,
    DateTime? serverTime,
    String? rejectionReason,
  }) {
    final companion = EventsCompanion(
      deliveryStatus: Value(status),
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
