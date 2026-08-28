import 'package:drift/drift.dart';

import 'common_fields.dart';
import 'inventory_items.dart';
import 'products.dart';

/// Proyección local de las presentaciones vendibles de un producto.
@DataClassName('ProductVariantRow')
class ProductVariants extends Table with CommonFields {
  /// Producto propietario de la variante. La cascada solo protege limpiezas
  /// tecnicas de proyecciones; no representa un borrado de negocio.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// Nombre visible normalizado de la variante; null representa una variante
  /// sin nombre capturado.
  TextColumn get name => text().nullable()();

  /// Clave NFKC en minúsculas derivada de [name] para unicidad por producto.
  TextColumn get nameKey => text().nullable()();

  /// Precio de venta entero expresado en la unidad monetaria menor. Siempre es
  /// positivo y es el único importe obligatorio de la variante.
  IntColumn get salePriceMinor => integer()();

  /// Costo estándar opcional en unidad monetaria menor. Null significa costo
  /// desconocido y cero significa costo conocido igual a cero.
  IntColumn get standardCostMinor => integer().nullable()();

  /// Recurso físico cuyo saldo sigue esta variante. Null significa que la
  /// variante no controla existencias. La unicidad mantiene el vínculo directo
  /// uno a uno sin transferir al catálogo la propiedad del recurso.
  TextColumn get inventoryItemId => text().nullable().unique().references(
    InventoryItems,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Indica que esta es la variante elegida por omisión.
  BoolColumn get isDefault => boolean()();

  /// Posición consecutiva dentro del producto, iniciando en cero.
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {productId, sortOrder},
    {productId, nameKey},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK ((name IS NULL) = (name_key IS NULL))',
    'CHECK (name IS NULL OR length(name) <= 160)',
    'CHECK (name_key IS NULL OR length(name_key) <= 320)',
    'CHECK (sale_price_minor > 0)',
    'CHECK (sale_price_minor <= 9007199254740991)',
    'CHECK (standard_cost_minor IS NULL OR '
        '(standard_cost_minor >= 0 AND '
        'standard_cost_minor <= 9007199254740991))',
    'CHECK (sort_order >= 0)',
  ];
}
