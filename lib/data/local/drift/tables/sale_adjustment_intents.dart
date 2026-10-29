import 'package:drift/drift.dart';

/// Diario durable de intenciones preparadas para recuperar IDs tras un fallo.
/// No usa CommonFields: sobre inmutable, sin proyección/active ni revisión.
@DataClassName('SaleAdjustmentIntentRow')
class SaleAdjustmentIntents extends Table {
  /// Identidad estable de documento, también única antes del commit comercial.
  TextColumn get operationId => text()();

  /// Identidad estable del evento, distinta de operación.
  TextColumn get eventId => text().unique()();

  /// Sobre completo serializado; permite recuperación sin regenerar IDs/fechas.
  TextColumn get eventJson => text()();
  @override
  Set<Column> get primaryKey => {operationId};
}
