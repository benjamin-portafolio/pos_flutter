import 'package:drift/drift.dart';

import 'categories.dart';
import 'common_fields.dart';
import 'units.dart';

/// Proyeccion local del producto comercial creado desde Articulos.
/// Conserva la configuración común de venta que heredan todas las variantes
/// del artículo.
@DataClassName('ProductRow')
class Products extends Table with CommonFields {
  /// Nombre comercial visible del articulo.
  TextColumn get name => text().withLength(min: 1, max: 160)();

  /// Categoria opcional usada para organizar el articulo; `null` significa
  /// que el usuario eligio `Sin categoria`.
  TextColumn get categoryId => text().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Forma de captura de la cantidad vendida: unidad completa o medida.
  TextColumn get saleMode => text().customConstraint(
    "NOT NULL DEFAULT 'unit' CHECK (sale_mode IN ('unit', 'measured'))",
  )();

  /// Unidad activa de masa o volumen usada para una venta medida.
  TextColumn get saleUnitId => text().nullable().references(
    Units,
    #unitId,
    onDelete: KeyAction.restrict,
  )();

  /// Átomos de la unidad seleccionada a los que corresponde el precio.
  IntColumn get priceReferenceQuantityAtomic => integer().nullable()();

  @override
  List<String> get customConstraints => const [
    '''CHECK (
      (sale_mode = 'unit' AND sale_unit_id IS NULL AND
        price_reference_quantity_atomic IS NULL) OR
      (sale_mode = 'measured' AND sale_unit_id IS NOT NULL AND
        price_reference_quantity_atomic > 0)
    )''',
  ];

  @override
  Set<Column> get primaryKey => {id};
}
