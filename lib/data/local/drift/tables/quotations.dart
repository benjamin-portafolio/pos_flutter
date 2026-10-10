import 'package:drift/drift.dart';
import 'common_fields.dart';

/// Documento local emitido, independiente de sales y del catálogo. CommonFields
/// conserva identidad y trazabilidad; el estado visible se deriva de sales.
@DataClassName('QuotationRow')
@TableIndex.sql(
  'CREATE INDEX ix_quotations_listing ON quotations(user_id, device_id, issued_at_local DESC, id DESC)',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_quotations_current_sale ON quotations(current_sale_id) WHERE active = 1 AND current_sale_id IS NOT NULL',
)
class Quotations extends Table with CommonFields {
  /// Usuario que emitió el documento.
  TextColumn get userId => text()();

  /// Dispositivo que conserva el historial local.
  TextColumn get deviceId => text()();

  /// Emisión estable por intención, con precisión de segundos de SQLite/Drift.
  DateTimeColumn get issuedAtLocal => dateTime()();

  /// Identidad histórica del origen, sin FK porque limpiar lo elimina.
  TextColumn get sourceSaleId => text()();

  /// Revisión histórica del borrador capturado, sin FK a events.
  TextColumn get sourceDraftEventId => text()();

  /// Venta vinculada para derivar estado; sin FK para tolerar su limpieza.
  TextColumn get currentSaleId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    'CHECK(length(trim(user_id)) > 0 AND length(trim(device_id)) > 0)',
    'CHECK(length(trim(source_sale_id)) > 0 AND length(trim(source_draft_event_id)) > 0)',
    'CHECK(current_sale_id IS NULL OR length(trim(current_sale_id)) > 0)',
  ];
}
