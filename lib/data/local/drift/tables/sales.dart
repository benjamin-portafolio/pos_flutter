import 'package:drift/drift.dart';
import 'common_fields.dart';

/// Borrador local de venta. CommonFields.id es la identidad de la venta;
/// active indica borrado lógico, mientras status describe su ciclo de negocio.
@DataClassName('SaleRow')
@TableIndex.sql(
  "CREATE UNIQUE INDEX ux_sales_local_draft ON sales(user_id, device_id) WHERE active = 1 AND status = 'borrador'",
)
class Sales extends Table with CommonFields {
  /// Usuario que inició la captura; se conserva en cada edición.
  TextColumn get userId => text()();

  /// Dispositivo de origen del borrador.
  TextColumn get deviceId => text()();

  /// Estado de captura: borrador o descartada.
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
    "CHECK(status IN ('borrador', 'descartada'))",
    'CHECK(total_minor >= 0 AND total_minor <= 9007199254740991)',
  ];
}
