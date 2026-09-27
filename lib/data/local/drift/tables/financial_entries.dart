import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'financial_categories.dart';

/// Registros reales de ingresos y gastos adicionales. No duplican
/// `sale_payments` ni `customer_payments`; cada fila es un hecho financiero.
@DataClassName('FinancialEntryRow')
@TableIndex.sql(
  'CREATE INDEX ix_financial_entries_period ON financial_entries(occurred_at_ms, id)',
)
@TableIndex.sql(
  'CREATE INDEX ix_financial_entries_category ON financial_entries(category_id, occurred_at_ms, id)',
)
class FinancialEntries extends Table with CommonFields {
  /// Categoría financiera referenciada; `active` no participa. RESTRICT impide
  /// borrar una categoría con registros.
  TextColumn get categoryId => text().references(
    FinancialCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Snapshot del nombre de la categoría al capturar (1..100 code points).
  /// Permite consultar el registro aunque cambie la proyección de la categoría
  /// o exista una incidencia de dependencia.
  TextColumn get categoryNameSnapshot => text().customConstraint(
    'NOT NULL CHECK(length(category_name_snapshot) BETWEEN 1 AND 100)',
  )();

  /// Snapshot de dirección validado contra la categoría al aplicar.
  TextColumn get direction => text().customConstraint(
    "NOT NULL CHECK(direction IN ('in', 'out'))",
  )();

  /// Snapshot de naturaleza validado contra la categoría al aplicar (5 valores).
  TextColumn get nature => text().customConstraint(
    "NOT NULL CHECK(nature IN ('operating', 'capital', 'asset_purchase', 'inventory_purchase', 'financing'))",
  )();

  /// Importe en centavos, positivo y dentro del entero seguro
  /// (1..9007199254740991). Acumulación con BigInt en el repositorio.
  IntColumn get amountMinor => integer().customConstraint(
    'NOT NULL CHECK(amount_minor > 0 AND amount_minor <= 9007199254740991)',
  )();

  /// Moneda fija MXN.
  TextColumn get currency => text().customConstraint(
    "NOT NULL CHECK(currency = 'MXN')",
  )();

  /// Medio cash/transfer como strings, igual que los pagos actuales. Transfer
  /// nunca implica saldo de un cajón: es solo el medio del registro.
  TextColumn get method => text().customConstraint(
    "NOT NULL CHECK(method IN ('cash', 'transfer'))",
  )();

  /// Instante efectivo UTC en ms, separado de la captura local y del cursor
  /// `last_server_sequence`. Filtra períodos [from_ms, to_ms).
  IntColumn get occurredAtMs => integer().customConstraint(
    'NOT NULL CHECK(occurred_at_ms > 0 AND occurred_at_ms <= 9007199254740991)',
  )();

  /// Nota opcional, normalizada NFKC+trim y vacío->null (máx. 500 code points).
  TextColumn get notes => text().nullable().customConstraint(
    'CHECK(notes IS NULL OR length(notes) <= 500)',
  )();

  /// Referencia opcional con la misma normalización que `notes`.
  TextColumn get reference => text().nullable().customConstraint(
    'CHECK(reference IS NULL OR length(reference) <= 500)',
  )();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK(NOT (direction = 'in' AND nature IN ('asset_purchase', 'inventory_purchase')))",
  ];
}