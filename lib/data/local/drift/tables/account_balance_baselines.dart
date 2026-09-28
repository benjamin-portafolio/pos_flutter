import 'package:drift/drift.dart';
import 'common_fields.dart';

/// Saldo inicial declarado de la cuenta bancaria única.
///
/// Hecho único e inmutable: se declara una sola vez, desde cualquier terminal
/// (D5), y no es una sesión. No hay `status` operativo, ni columnas `closed_*`,
/// ni snapshot de cierre, ni notas: la fila existe o no existe, y una vez
/// escrita no se modifica. Entrega en `events`, igual que caja.
///
/// Sin `account_id` (fuera de alcance explicito, R4): el slot único lo
/// resuelve la referencia `requires_unique` de refId constante, no una columna.
@DataClassName('AccountBalanceBaselineRow')
class AccountBalanceBaselines extends Table with CommonFields {
  /// Terminal que declaró el saldo. Se registra para trazabilidad, NO limita
  /// la unicidad: cualquiera terminal puede declarar.
  TextColumn get deviceId => text()();

  /// Responsable que hizo la declaración.
  TextColumn get declaredByUserId => text()();

  /// Saldo reportado por el banco en centavos.
  ///
  /// ADMITE NEGATIVO a propósito: una cuenta puede estar sobregirada y esa es
  /// una declaración legítima. Es la única divergencia de rango frente al resto
  /// del esquema (`cash_sessions.opening_minor` prohíbe negativos), y es
  /// deliberada: recortar a cero corrompería el estimado en silencio (R3).
  IntColumn get amountMinor => integer()();

  /// FRONTERA en UTC ms: el saldo declarado cubre todo lo anterior a este
  /// instante. Fase 4 suma solo los movimientos posteriores.
  IntColumn get asOfMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK(amount_minor BETWEEN -9007199254740991 AND 9007199254740991)',
    'CHECK(as_of_ms BETWEEN 1 AND 9007199254740991)',
  ];
}
