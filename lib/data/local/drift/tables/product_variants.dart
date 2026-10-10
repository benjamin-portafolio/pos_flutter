import 'package:drift/drift.dart';

import 'common_fields.dart';
import 'inventory_items.dart';
import 'products.dart';

/// Proyección local de las presentaciones vendibles de un producto.
@DataClassName('ProductVariantRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_product_variants_product_sort ON product_variants (product_id, sort_order) WHERE active = 1',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_product_variants_product_name_key ON product_variants (product_id, name_key) WHERE active = 1 AND name_key IS NOT NULL',
)
class ProductVariants extends Table with CommonFields {
  /// Producto propietario. La cascada elimina sus variantes cuando el comando
  /// de eliminación borra el producto o se reconstruye la proyección.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// Nombre visible normalizado de la variante; null representa una variante
  /// sin nombre capturado.
  TextColumn get name => text().nullable()();

  /// Clave NFKC en minúsculas derivada de [name] para unicidad por producto.
  TextColumn get nameKey => text().nullable()();

  /// Código de barras opcional, solo dígitos de hasta 32 caracteres. Se guarda
  /// como texto y no se interpreta numéricamente para conservar los ceros a la
  /// izquierda de UPC-A y admitir GS1-128. Null significa variante sin código.
  TextColumn get barcode => text().nullable()();

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

  /// Posición consecutiva entre variantes activas; las inactivas conservan su posición histórica.
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK ((name IS NULL) = (name_key IS NULL))',
    'CHECK (name IS NULL OR length(name) <= 160)',
    'CHECK (name_key IS NULL OR length(name_key) <= 320)',
    // SQLite no admite el operador ~; NOT GLOB cumple el mismo papel.
    'CHECK (barcode IS NULL OR '
        '(length(barcode) BETWEEN 1 AND 32 AND barcode NOT GLOB \'*[^0-9]*\'))',
    'CHECK (sale_price_minor > 0)',
    'CHECK (sale_price_minor <= 9007199254740991)',
    'CHECK (standard_cost_minor IS NULL OR '
        '(standard_cost_minor >= 0 AND '
        'standard_cost_minor <= 9007199254740991))',
    'CHECK (sort_order >= 0)',
  ];
}
