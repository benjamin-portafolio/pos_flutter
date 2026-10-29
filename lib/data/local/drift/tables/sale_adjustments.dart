import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'sales.dart';
import 'events.dart';
import 'sale_payments.dart';
import 'clientes.dart';

/// Documento compensatorio; originales y entrega permanecen en sus tablas.
@DataClassName('SaleAdjustmentRow')
@TableIndex.sql(
  "CREATE UNIQUE INDEX ux_sale_void ON sale_adjustments(sale_id) WHERE kind = 'void' AND commercial_active = 1",
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_sale_adjustment_revision ON sale_adjustments(sale_id, revision) WHERE commercial_active = 1',
)
class SaleAdjustments extends Table with CommonFields {
  /// Rama comercial vigente; false conserva documento físico en incidencia.
  BoolColumn get commercialActive =>
      boolean().withDefault(const Constant(true))();

  /// Venta confirmada que conserva su identidad y fecha.
  TextColumn get saleId => text().references(Sales, #id)();

  /// Evento original autoritativo; nunca una base de catálogo actual.
  @ReferenceName('adjustmentConfirmations')
  TextColumn get confirmationEventId => text().references(Events, #eventId)();

  /// Base comercial inmediata, confirmación o ajuste anterior.
  @ReferenceName('adjustmentBases')
  TextColumn get baseEventId => text().references(Events, #eventId)();

  /// Evento único de este documento (id heredado es operation_id).
  @ReferenceName('adjustmentEvents')
  TextColumn get eventId => text().unique().references(Events, #eventId)();

  /// void o return; no representa el estado de entrega.
  TextColumn get kind => text()();

  /// Revisión comercial producida, comenzando en uno.
  IntColumn get revision => integer()();

  /// Día de negocio congelado, independiente de la fecha original.
  TextColumn get businessDate => text()();

  /// Instante congelado de la operación en milisegundos UTC.
  IntColumn get occurredAtMs => integer()();

  /// Offset histórico capturado al preparar la intención.
  IntColumn get utcOffsetMinutes => integer()();

  /// Motivo normalizado obligatorio.
  TextColumn get reason => text()();

  /// Autor estable de la intención.
  TextColumn get userId => text()();

  /// Terminal estable de la intención.
  TextColumn get deviceId => text()();

  /// Importe compensado, en centavos; admite residuo cero.
  IntColumn get amountMinor => integer()();

  /// Método original: cash, transfer o credit.
  TextColumn get method => text()();

  /// Pago original compensado; ausente exclusivamente en crédito.
  TextColumn get salePaymentId =>
      text().nullable().references(SalePayments, #id)();

  /// Cliente histórico del documento, obligatorio para reducir crédito.
  TextColumn get clienteId => text().nullable().references(Clientes, #id)();

  /// Moneda congelada de la venta y de la operación.
  TextColumn get currency => text()();

  /// Referencia declarada de devolución por transferencia; no ejecuta banco.
  TextColumn get settlementReference => text().nullable()();

  /// Configuración de caja observada y validada al realizar la operación.
  BoolColumn get cashEnabled => boolean()();

  /// Declaración de liquidación física o contable.
  TextColumn get settlementAction => text()();

  /// Payload canónico completo: referencia, liquidación, destinos y orígenes.
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK(kind IN ('void','return'))",
    'CHECK(revision > 0)',
    "CHECK(currency = 'MXN')",
    "CHECK(method IN ('cash','transfer','credit'))",
    "CHECK((method = 'credit' AND sale_payment_id IS NULL AND cliente_id IS NOT NULL) OR (method IN ('cash','transfer') AND sale_payment_id IS NOT NULL))",
    'CHECK(amount_minor BETWEEN 0 AND 9007199254740991)',
    'CHECK(length(trim(reason)) BETWEEN 1 AND 500 AND reason = trim(reason))',
  ];
}
