import 'package:drift/drift.dart';
import 'inventory_items.dart';
import 'product_variants.dart';
import 'supplier_orders.dart';
import 'units.dart';

/// Hijo del pedido; sin versión propia. La base del pedido serializa toda escritura.
@DataClassName('SupplierOrderItemRow')
@TableIndex.sql(
  'CREATE INDEX ix_supplier_order_items_lookup ON supplier_order_items (variant_id, order_id)',
)
class SupplierOrderItems extends Table {
  /// Identidad UUID estable, independiente de la posición.
  TextColumn get id => text()();

  /// order_id: pedido propietario y frontera de concurrencia.
  TextColumn get orderId =>
      text().references(SupplierOrders, #id, onDelete: KeyAction.restrict)();

  /// Variante original; una sola partida por variante y pedido.
  TextColumn get variantId =>
      text().references(ProductVariants, #id, onDelete: KeyAction.restrict)();

  /// Recurso histórico exacto al que se recibirá; nunca redirigir a otro vínculo.
  TextColumn get inventoryItemId =>
      text().references(InventoryItems, #id, onDelete: KeyAction.restrict)();

  /// Unidad cuya identidad queda congelada; se valida antes de recibir.
  TextColumn get unitId =>
      text().references(Units, #unitId, onDelete: KeyAction.restrict)();

  /// Nombre del producto congelado para lectura histórica.
  TextColumn get productNameSnapshot => text()();

  /// Nombre opcional de la variante congelado para lectura histórica.
  TextColumn get variantNameSnapshot => text().nullable()();

  /// Dimensión física count/mass/volume del recurso capturado.
  TextColumn get dimension => text()();

  /// Código capturado de unidad; no depende de cambios de catálogo.
  TextColumn get unitCodeSnapshot => text()();

  /// Símbolo capturado que acompaña la cantidad documental.
  TextColumn get unitSymbolSnapshot => text()();

  /// Átomos por unidad mostrada; entero positivo seguro.
  IntColumn get unitAtomicFactor => integer()();

  /// Cantidad atómica por la que se cotizó el precio capturado.
  IntColumn get referenceQuantityAtomic => integer()();

  /// Cantidad positiva pedida o realmente recibida en átomos; nunca saldo absoluto.
  IntColumn get quantityAtomic => integer()();

  /// Precio estimado en unidad menor; null desconocido, cero explícito.
  IntColumn get quotedPriceMinor => integer().nullable()();

  /// Importe estimado redondeado de la partida; null junto con el precio desconocido.
  IntColumn get totalMinor => integer().nullable()();

  /// Faltante cerrado explícitamente; no genera inventario ni se edita desde UI.
  IntColumn get closedQuantityAtomic =>
      integer().withDefault(const Constant(0))();

  /// Orden visual 0..49, único por pedido; no es identidad de la partida.
  IntColumn get position => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK (typeof(unit_atomic_factor) = 'integer' AND unit_atomic_factor BETWEEN 1 AND 9007199254740991)",
    "CHECK (typeof(reference_quantity_atomic) = 'integer' AND reference_quantity_atomic BETWEEN 1 AND 9007199254740991)",
    "CHECK (typeof(quantity_atomic) = 'integer' AND quantity_atomic BETWEEN 1 AND 9007199254740991)",
    "CHECK (quoted_price_minor IS NULL OR (typeof(quoted_price_minor) = 'integer' AND quoted_price_minor BETWEEN 0 AND 9007199254740991))",
    "CHECK (total_minor IS NULL OR (typeof(total_minor) = 'integer' AND total_minor BETWEEN 0 AND 9007199254740991))",
    "CHECK (typeof(closed_quantity_atomic) = 'integer' AND closed_quantity_atomic BETWEEN 0 AND 9007199254740991)",
    "CHECK (dimension IN ('count','mass','volume'))",
    "CHECK (length(product_name_snapshot) BETWEEN 1 AND 160)",
    "CHECK (variant_name_snapshot IS NULL OR length(variant_name_snapshot) <= 160)",
    "CHECK (length(unit_code_snapshot) BETWEEN 1 AND 16)",
    "CHECK (length(unit_symbol_snapshot) BETWEEN 1 AND 16)",
    "CHECK (dimension <> 'count' OR (unit_atomic_factor = 1 AND reference_quantity_atomic = 1))",
    "CHECK (closed_quantity_atomic <= quantity_atomic)",
    "CHECK (position BETWEEN 0 AND 49)",
    "UNIQUE (order_id, position)",
    "UNIQUE (order_id, variant_id)",
    "UNIQUE (order_id, id)",
    "CHECK ((quoted_price_minor IS NULL) = (total_minor IS NULL))",
  ];
}
