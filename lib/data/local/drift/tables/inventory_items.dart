import 'package:drift/drift.dart';

import 'common_fields.dart';
import 'units.dart';

/// Proyección local del recurso cuya existencia se controla en inventario.
@DataClassName('InventoryItemRow')
class InventoryItems extends Table with CommonFields {
  /// Unidad elegida para capturar y mostrar existencias del recurso.
  TextColumn get defaultUnitId =>
      text().references(Units, #unitId, onDelete: KeyAction.restrict)();

  /// Nombre descriptivo; no es único por regla de negocio.
  TextColumn get name => text().withLength(min: 1, max: 160)();

  @override
  Set<Column> get primaryKey => {id};
}
