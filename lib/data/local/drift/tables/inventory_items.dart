import 'package:drift/drift.dart';

import 'common_fields.dart';
import 'units.dart';

/// Proyección local del recurso cuya existencia se controla en inventario.
@DataClassName('InventoryItemRow')
@TableIndex.sql(
  'CREATE INDEX ix_inventory_items_origin_variant ON inventory_items (origin_variant_id)',
)
class InventoryItems extends Table with CommonFields {
  /// Unidad elegida para capturar y mostrar existencias del recurso.
  TextColumn get defaultUnitId =>
      text().references(Units, #unitId, onDelete: KeyAction.restrict)();

  /// Nombre descriptivo; no es único por regla de negocio.
  TextColumn get name => text().withLength(min: 1, max: 160)();

  /// Variante que originó este recurso, escrita solo por
  /// `recurso_inventario_creado`. Renombrar el recurso o mover su stock no la
  /// modifica.
  ///
  /// Es una identidad de procedencia y **no** una FK: el evento de recurso se
  /// aplica antes de que exista la variante, de modo que declarar la
  /// referencia invertaría el orden causal recurso → producto. El formato UUID
  /// v4 se valida en el contrato del evento.
  ///
  /// El índice es deliberadamente no único: pueden existir recursos históricos
  /// o creaciones concurrentes con el mismo origen, y la unicidad normativa
  /// sigue siendo la del vínculo directo de `product_variants`. Null significa
  /// procedencia desconocida (recursos independientes y eventos legados) y no
  /// autoriza ningún descarte.
  TextColumn get originVariantId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
