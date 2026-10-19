import 'package:drift/drift.dart';

/// Diario de capturas confirmadas, exclusivamente local y duradero. Protege
/// frente a reintentos incluso después de perder la respuesta del commit.
/// Excepción a CommonFields: no es una proyección/evento sincronizable, no tiene
/// active, versión de agregado, evento creador ni secuencia de servidor. Su
/// estado describe ejecución local y nunca aceptación remota. No se purga al
/// entregar eventos; el reset de desarrollo sí elimina esta evidencia.
@DataClassName('BulkEditOperationRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_bulk_edit_batch_product ON bulk_edit_operations(batch_id, product_id)',
)
class BulkEditOperations extends Table {
  /// Identidad determinista de captura/producto, reutilizada en cada reintento.
  TextColumn get operationId => text()();

  /// Identidad estable de la revisión confirmada, no del borrador sin confirmar.
  TextColumn get batchId => text()();

  /// Producto destino; sin FK para conservar evidencia si se elimina después.
  TextColumn get productId => text()();

  /// Modo al confirmar; impide continuar pendientes bajo otro modo.
  TextColumn get mode => text()();

  /// JSON canónico versionado: variantes, intención explícita, proveedor/fecha,
  /// bases de producto/recurso/saldo, vínculo, unidad y cantidades confirmados.
  TextColumn get intentJson => text()();

  /// confirmada, aplicada o cerrada; los fallos dejan la reserva confirmada.
  TextColumn get localState => text()();

  /// Resultado tipado con IDs originales de eventos/movimientos, solo aplicada.
  TextColumn get resultJson => text().nullable()();

  /// Instante UTC de reserva del conjunto confirmado antes de iniciar negocio.
  DateTimeColumn get confirmedAt => dateTime()();

  /// Instante UTC del commit aplicado o del cierre explícito de la propuesta.
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {operationId};

  @override
  List<String> get customConstraints => const [
    "CHECK (mode IN ('standalone', 'server_sync'))",
    "CHECK (local_state IN ('confirmada', 'aplicada', 'cerrada'))",
    "CHECK ((local_state = 'aplicada') = (result_json IS NOT NULL))",
    "CHECK ((local_state = 'confirmada') = (finished_at IS NULL))",
  ];
}
