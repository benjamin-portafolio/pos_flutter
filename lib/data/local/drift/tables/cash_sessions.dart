import 'package:drift/drift.dart';
import 'common_fields.dart';

/// Caja operativa de un dispositivo; active permanece true. Entrega en events.
@DataClassName('CashSessionRow')
@TableIndex.sql(
  "CREATE UNIQUE INDEX uq_cash_session_open_device ON cash_sessions(device_id) WHERE status = 'open'",
)
class CashSessions extends Table with CommonFields {
  /// Único dispositivo escritor autorizado por esta apertura.
  TextColumn get deviceId => text()();

  /// Responsable que abrió el cajón.
  TextColumn get openedByUserId => text()();

  /// Responsable del cierre, nulo mientras está abierto.
  TextColumn get closedByUserId => text().nullable()();

  /// Estado operativo open/closed, independiente de entrega.
  TextColumn get status => text()();

  /// Apertura UTC ms; no decide pertenencia de movimientos.
  IntColumn get openedAtMs => integer()();

  /// Cierre UTC ms, nulo mientras está abierto.
  IntColumn get closedAtMs => integer().nullable()();

  /// Fondo inicial en centavos; no genera movimiento adicional.
  IntColumn get openingMinor => integer()();

  /// Efectivo contado en centavos al cerrar.
  IntColumn get countedMinor => integer().nullable()();

  /// Total exacto de entradas en decimal, evitando overflow acumulado.
  TextColumn get incomeMinor => text().nullable()();

  /// Total exacto de salidas en decimal.
  TextColumn get expenseMinor => text().nullable()();

  /// Fondo + entradas - salidas congelado al cerrar.
  TextColumn get expectedMinor => text().nullable()();

  /// Contado - esperado congelado al cerrar.
  TextColumn get differenceMinor => text().nullable()();

  /// Payload completo del corte y su conjunto verificable, JSON inmutable.
  TextColumn get closeSnapshot => text().nullable()();

  /// Dependencia causal con el cierre previo del mismo dispositivo.
  TextColumn get previousCloseEventId => text().nullable()();

  /// Nota opcional del cierre normalizada.
  TextColumn get notes => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK(status IN ('open','closed'))",
    'CHECK(opening_minor BETWEEN 0 AND 9007199254740991)',
    'CHECK(counted_minor IS NULL OR counted_minor BETWEEN 0 AND 9007199254740991)',
    "CHECK((status = 'open' AND closed_at_ms IS NULL AND closed_by_user_id IS NULL AND counted_minor IS NULL AND close_snapshot IS NULL AND income_minor IS NULL AND expense_minor IS NULL AND expected_minor IS NULL AND difference_minor IS NULL) OR (status = 'closed' AND closed_at_ms IS NOT NULL AND closed_by_user_id IS NOT NULL AND counted_minor IS NOT NULL AND close_snapshot IS NOT NULL AND income_minor IS NOT NULL AND expense_minor IS NOT NULL AND expected_minor IS NOT NULL AND difference_minor IS NOT NULL))",
    'CHECK(notes IS NULL OR length(notes) <= 500)',
  ];
}
