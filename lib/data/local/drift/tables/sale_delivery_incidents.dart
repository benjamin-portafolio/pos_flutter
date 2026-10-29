import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'events.dart';
import 'sales.dart';

/// Incidencia durable: no borra ni compensa automáticamente hechos físicos.
class SaleDeliveryIncidents extends Table with CommonFields {
  /// Venta bloqueada para nuevas intenciones hasta conciliación explícita.
  TextColumn get saleId => text().references(Sales, #id)();

  /// Evento local cuya evidencia permanece; id heredado usa esta identidad estable.
  @ReferenceName('incidentLosers')
  TextColumn get loserEventId => text().unique().references(Events, #eventId)();

  /// Ganador oficial, cuando se conoce; puede llegar posteriormente por pull.
  @ReferenceName('incidentWinners')
  TextColumn get winnerEventId =>
      text().nullable().references(Events, #eventId)();

  /// Dependencia terminal, si la incidencia fue propagada causalmente.
  TextColumn get blockedByEventId => text().nullable()();

  /// Causa visible de entrega, independiente del estado comercial.
  TextColumn get reason => text()();

  /// Payload congelado con IDs, importes, destinos, fecha y caja de origen.
  TextColumn get preservedPayloadJson => text()();

  /// Evento de conciliación que consumirá la evidencia en sesión 4.
  TextColumn get resolutionEventId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}
