import 'package:drift/drift.dart';

import 'product_variants.dart';
import 'suppliers.dart';

/// Precio vigente por pareja variante/proveedor; no cambia venta, costo o stock.
/// Excepción a CommonFields: hijo reemplazable del agregado producto, como
/// recipe_components. La clave compuesta identifica la relación; no tiene
/// active, versión ni eventos independientes. El producto conserva su base y
/// la trazabilidad/reversión del conjunto. Sin índice por proveedor hasta que
/// exista una consulta que lo necesite.
@DataClassName('VariantSupplierRow')
class VariantSuppliers extends Table {
  /// Variante propietaria; su borrado físico elimina las relaciones en cascada.
  TextColumn get variantId =>
      text().references(ProductVariants, #id, onDelete: KeyAction.cascade)();

  /// Proveedor existente; RESTRICT impide borrarlo mientras esté relacionado.
  TextColumn get supplierId =>
      text().references(Suppliers, #id, onDelete: KeyAction.restrict)();

  /// Entero no negativo en unidad monetaria menor (0 es un precio explícito).
  /// Por unidad de la variante o cantidad de referencia del producto medido.
  IntColumn get quotedPriceMinor => integer()();

  /// Fecha informada UTC en milisegundos Unix; no es un reloj de concurrencia.
  IntColumn get quotedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {variantId, supplierId};

  @override
  List<String> get customConstraints => [
    "CHECK (typeof(quoted_price_minor) = 'integer' AND quoted_price_minor BETWEEN 0 AND 9007199254740991)",
    "CHECK (typeof(quoted_at_ms) = 'integer' AND quoted_at_ms BETWEEN 1 AND 9007199254740991)",
  ];
}
