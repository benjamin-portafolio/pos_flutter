import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'quotations.dart';

/// Líneas inmutables del documento emitido, con IDs propios. CommonFields
/// conserva identidad y trazabilidad. No depende del catálogo ni del borrador.
@DataClassName('QuotationItemRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_quotation_items_order ON quotation_items(quotation_id, sort_order)',
)
class QuotationItems extends Table with CommonFields {
  /// Documento propietario; impide dejar líneas huérfanas.
  TextColumn get quotationId =>
      text().references(Quotations, #id, onDelete: KeyAction.restrict)();

  /// Variante histórica sin FK: el documento sobrevive al catálogo.
  TextColumn get variantId => text()();

  /// Nombre del producto al emitir el documento.
  TextColumn get productNameSnapshot => text()();

  /// Nombre opcional de la variante al emitir el documento.
  TextColumn get variantNameSnapshot => text().nullable()();

  /// Modo capturado: unit o measured.
  TextColumn get saleModeSnapshot => text()();

  /// Conteo entero positivo en unit; null en measured.
  IntColumn get quantity => integer().nullable()();

  /// Cantidad atómica positiva en measured; null en unit.
  IntColumn get measuredQuantityAtomic => integer().nullable()();

  /// Código original de la unidad medida; null en unit.
  TextColumn get saleUnitCodeSnapshot => text().nullable()();

  /// Símbolo original para presentar la cantidad; null en unit.
  TextColumn get saleUnitSymbolSnapshot => text().nullable()();

  /// Átomos por unidad de presentación original; null en unit.
  IntColumn get saleUnitAtomicFactorSnapshot => integer().nullable()();

  /// Orden estable dentro del documento, desde cero.
  IntColumn get sortOrder => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    'CHECK(sort_order >= 0 AND sort_order <= 9007199254740991)',
    """CHECK((sale_mode_snapshot = 'unit' AND quantity IS NOT NULL AND quantity > 0 AND quantity <= 9007199254740991
      AND measured_quantity_atomic IS NULL
      AND sale_unit_code_snapshot IS NULL AND sale_unit_symbol_snapshot IS NULL AND sale_unit_atomic_factor_snapshot IS NULL)
      OR (sale_mode_snapshot = 'measured' AND quantity IS NULL
      AND measured_quantity_atomic IS NOT NULL AND measured_quantity_atomic > 0 AND measured_quantity_atomic <= 9007199254740991
      AND sale_unit_atomic_factor_snapshot IS NOT NULL AND sale_unit_atomic_factor_snapshot > 0 AND sale_unit_atomic_factor_snapshot <= 9007199254740991
      AND sale_unit_code_snapshot IS NOT NULL AND length(trim(sale_unit_code_snapshot)) > 0
      AND sale_unit_symbol_snapshot IS NOT NULL AND length(trim(sale_unit_symbol_snapshot)) > 0))""",
  ];
}
