import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'clientes.dart';

/// Venta local, en borrador o confirmada. CommonFields.id identifica la venta;
/// active indica borrado lógico, mientras status describe su ciclo de negocio.
@DataClassName('SaleRow')
@TableIndex.sql(
  "CREATE INDEX ix_sales_local_drafts ON sales(user_id, device_id, created_at_local, id) WHERE active = 1 AND status = 'borrador'",
)
class Sales extends Table with CommonFields {
  /// Versión del contrato de precio; null conserva confirmaciones históricas.
  IntColumn get pricingContractVersion => integer().nullable().customConstraint(
    'NULL CHECK (pricing_contract_version IS NULL OR pricing_contract_version = 2)',
  )();

  /// Elección global; null = histórico desconocido; borrador legado usa normal al leer.
  TextColumn get pricingMode => text().nullable().customConstraint(
    "NULL CHECK (pricing_mode IS NULL OR pricing_mode IN ('normal','offer'))",
  )();

  /// Cliente opcional en efectivo y obligatorio al confirmar a crédito.
  TextColumn get clienteId => text().nullable().references(Clientes, #id)();

  /// Usuario que inició la captura; se conserva en cada edición.
  TextColumn get userId => text()();

  /// Dispositivo de origen del borrador.
  TextColumn get deviceId => text()();

  /// Estado de negocio: borrador, descartada o confirmada; independiente de sync.
  TextColumn get status => text().withDefault(const Constant('borrador'))();

  /// Suma en centavos de líneas activas, recalculada en la misma transacción.
  IntColumn get totalMinor => integer()();

  /// Fecha local original de creación, conservada al editar.
  DateTimeColumn get createdAtLocal => dateTime()();

  /// Fecha local de la última modificación.
  DateTimeColumn get updatedAtLocal => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK(status IN ('borrador', 'descartada', 'confirmada'))",
    'CHECK(total_minor >= 0 AND total_minor <= 9007199254740991)',
  ];
}
