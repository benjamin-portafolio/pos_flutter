import 'package:drift/drift.dart';

import 'inventory_items.dart';
import 'product_variants.dart';

/// Relación que expresa qué recursos consume la receta de una variante.
@DataClassName('RecipeComponentRow')
class RecipeComponents extends Table {
  /// Variante cuya receta contiene el recurso.
  TextColumn get variantId =>
      text().references(ProductVariants, #id, onDelete: KeyAction.cascade)();

  /// Recurso consumido por la receta.
  TextColumn get inventoryItemId =>
      text().references(InventoryItems, #id, onDelete: KeyAction.restrict)();

  /// Cantidad atómica positiva consumida por una unidad vendida.
  IntColumn get quantityAtomic =>
      integer().customConstraint('NOT NULL CHECK (quantity_atomic > 0)')();

  @override
  Set<Column> get primaryKey => {variantId, inventoryItemId};
}
