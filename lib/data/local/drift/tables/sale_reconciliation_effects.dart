import 'package:drift/drift.dart';
import 'events.dart';

/// Contenido inmutable de regularizaciones independientes. No usa CommonFields:
/// es un libro por identidad física, sin versión/active comercial. La asociación
/// a una declaración y el marcador de aplicación local solo controlan consumo
/// e idempotencia; la trazabilidad del documento se conserva en Events.
/// No altera cantidades devueltas ni la evidencia congelada de un corte.
class SaleReconciliationEffects extends Table {
  /// Identidad física preservada o recuperación declarada; consumo global único.
  TextColumn get effectId => text()();

  /// Evento de conciliación dueño del consumo de esta evidencia.
  TextColumn get eventId => text().references(Events, #eventId)();

  /// Stock, caja, crédito o transferencia; unidad determinada por el libro.
  TextColumn get ledger => text()();

  /// Recurso, cuenta de cliente o identidad monetaria de origen.
  TextColumn get targetId => text()();

  /// Diferencia firmada en unidades atómicas o centavos.
  IntColumn get delta => integer()();

  /// Sesión histórica del efectivo, sin reescribir su corte.
  TextColumn get cashSessionId => text().nullable()();

  /// Evidencia completa tipada con fecha y apertura histórica.
  TextColumn get payloadJson => text()();

  /// Distingue el reconocimiento de evidencia de un acto posterior declarado.
  BoolColumn get isRecovery => boolean()();

  /// El efecto ya está en el libro físico de esta instalación.
  BoolColumn get appliedLocally => boolean()();
  @override
  Set<Column> get primaryKey => {effectId};
}
