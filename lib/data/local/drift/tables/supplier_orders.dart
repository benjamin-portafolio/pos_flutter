import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'suppliers.dart';

/// Pedido con trazabilidad propia; sus partidas comparten la base del agregado.
@DataClassName('SupplierOrderRow')
@TableIndex.sql(
  'CREATE INDEX ix_supplier_orders_lookup ON supplier_orders (supplier_id, status, occurred_at_ms)',
)
class SupplierOrders extends Table with CommonFields {
  /// supplier_id: identidad del proveedor; el snapshot conserva su presentación.
  TextColumn get supplierId =>
      text().references(Suppliers, #id, onDelete: KeyAction.restrict)();

  /// Estado del documento; los terminales no admiten edición en el flujo de negocio.
  TextColumn get status => text()();

  /// Fecha informada UTC en milisegundos; no arbitra concurrencia.
  IntColumn get occurredAtMs => integer()();

  /// Moneda documental de tres letras; no implica cuenta por pagar.
  TextColumn get currency => text()();

  /// Nombre del proveedor congelado al confirmar; no consultar catálogo para imprimir.
  TextColumn get supplierNameSnapshot => text()();

  /// Teléfono capturado opcional del proveedor para interpretar el documento.
  TextColumn get supplierPhoneSnapshot => text().nullable()();

  /// Notas opcionales del documento, hasta 1000 caracteres.
  TextColumn get notes => text().nullable()();

  /// Importe estimado; null si cualquier partida carece de precio conocido.
  IntColumn get totalMinor => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK (typeof(occurred_at_ms) = 'integer' AND occurred_at_ms BETWEEN 1 AND 9007199254740991)",
    "CHECK (total_minor IS NULL OR (typeof(total_minor) = 'integer' AND total_minor BETWEEN 0 AND 9007199254740991))",
    "CHECK (status IN ('draft','confirmed','partial','received','closed','cancelled'))",
    "CHECK (length(currency) = 3)",
    "CHECK (length(supplier_name_snapshot) BETWEEN 1 AND 160)",
    "CHECK (supplier_phone_snapshot IS NULL OR length(supplier_phone_snapshot) <= 80)",
    "CHECK (notes IS NULL OR length(notes) <= 1000)",
  ];
}
