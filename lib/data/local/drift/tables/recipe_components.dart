import 'package:drift/drift.dart';

import 'inventory_items.dart';
import 'product_variants.dart';

/// Componentes actuales de la receta de una variante.
///
/// No usa `CommonFields` porque cada fila es un hijo reemplazable sin ciclo,
/// versión ni trazabilidad independientes. La variante y su evento contienen
/// la concurrencia y trazabilidad del conjunto completo.
@DataClassName('RecipeComponentRow')
@TableIndex.sql(
  'CREATE INDEX ix_recipe_components_inventory_item '
  'ON recipe_components (inventory_item_id)',
)
class RecipeComponents extends Table {
  /// Variante cuya receta consume el recurso. La cascada solo protege
  /// reconstrucciones técnicas de la proyección.
  TextColumn get variantId =>
      text().references(ProductVariants, #id, onDelete: KeyAction.cascade)();

  /// Recurso de inventario consumido. Un recurso no se repite dentro de la
  /// misma receta y no puede borrarse mientras permanezca referenciado.
  TextColumn get inventoryItemId =>
      text().references(InventoryItems, #id, onDelete: KeyAction.restrict)();

  /// Consumo normalizado al átomo del recurso por unidad vendida o por la
  /// cantidad de referencia de un producto medido.
  IntColumn get quantityAtomic => integer()();

  @override
  Set<Column> get primaryKey => {variantId, inventoryItemId};

  @override
  List<String> get customConstraints => [
    'CHECK (quantity_atomic > 0)',
    'CHECK (quantity_atomic <= 9007199254740991)',
  ];
}
