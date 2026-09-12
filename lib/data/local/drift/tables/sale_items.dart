import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'sales.dart';
import 'product_variants.dart';

/// Líneas de la captura local. CommonFields.id identifica la línea y active
/// determina si participa en el total. Version y trazabilidad son heredadas.
@DataClassName('SaleItemRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_sale_items_order ON sale_items(sale_id, sort_order)',
)
class SaleItems extends Table with CommonFields {
  /// Venta propietaria; no permite eliminar una venta con líneas.
  TextColumn get saleId =>
      text().references(Sales, #id, onDelete: KeyAction.restrict)();

  /// Variante capturada; protege la referencia frente al borrado físico.
  TextColumn get variantId =>
      text().references(ProductVariants, #id, onDelete: KeyAction.restrict)();

  /// Nombre del producto al agregar la línea.
  TextColumn get productNameSnapshot => text()();

  /// Nombre opcional de la variante al agregar la línea.
  TextColumn get variantNameSnapshot => text().nullable()();

  /// Modo capturado: unit o measured.
  TextColumn get saleModeSnapshot => text()();

  /// Conteo entero positivo en unit; null en measured.
  IntColumn get quantity => integer().nullable()();

  /// Cantidad atómica positiva en measured; null en unit.
  IntColumn get measuredQuantityAtomic => integer().nullable()();

  /// Precio capturado en centavos por pieza o por cantidad de referencia.
  IntColumn get unitPriceMinor => integer()();

  /// Costo estándar capturado; null conserva que se desconoce el costo.
  IntColumn get standardCostMinorSnapshot => integer().nullable()();

  /// Cantidad atómica a la que corresponde el precio medido; null en unit.
  IntColumn get priceReferenceQuantityAtomicSnapshot => integer().nullable()();

  /// Código original de la unidad medida; null en unit.
  TextColumn get saleUnitCodeSnapshot => text().nullable()();

  /// Símbolo original para presentar la cantidad; null en unit.
  TextColumn get saleUnitSymbolSnapshot => text().nullable()();

  /// Átomos por unidad de presentación original; null en unit.
  IntColumn get saleUnitAtomicFactorSnapshot => integer().nullable()();

  /// Importe de la línea con redondeo half-up sobre su cantidad total.
  IntColumn get totalMinor => integer()();

  /// Orden estable dentro de la venta, desde cero.
  IntColumn get sortOrder => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    'CHECK(unit_price_minor > 0 AND unit_price_minor <= 9007199254740991)',
    'CHECK(total_minor >= 0 AND total_minor <= 9007199254740991)',
    'CHECK(standard_cost_minor_snapshot IS NULL OR (standard_cost_minor_snapshot >= 0 AND standard_cost_minor_snapshot <= 9007199254740991))',
    'CHECK(sort_order >= 0)',
    """CHECK((sale_mode_snapshot = 'unit' AND quantity IS NOT NULL AND quantity > 0 AND quantity <= 9007199254740991
      AND measured_quantity_atomic IS NULL AND price_reference_quantity_atomic_snapshot IS NULL
      AND sale_unit_code_snapshot IS NULL AND sale_unit_symbol_snapshot IS NULL AND sale_unit_atomic_factor_snapshot IS NULL)
      OR (sale_mode_snapshot = 'measured' AND quantity IS NULL
      AND measured_quantity_atomic IS NOT NULL AND measured_quantity_atomic > 0 AND measured_quantity_atomic <= 9007199254740991
      AND price_reference_quantity_atomic_snapshot IS NOT NULL AND price_reference_quantity_atomic_snapshot > 0 AND price_reference_quantity_atomic_snapshot <= 9007199254740991
      AND sale_unit_atomic_factor_snapshot IS NOT NULL AND sale_unit_atomic_factor_snapshot > 0 AND sale_unit_atomic_factor_snapshot <= 9007199254740991
      AND sale_unit_code_snapshot IS NOT NULL AND length(trim(sale_unit_code_snapshot)) > 0
      AND sale_unit_symbol_snapshot IS NOT NULL AND length(trim(sale_unit_symbol_snapshot)) > 0))""",
  ];
}
