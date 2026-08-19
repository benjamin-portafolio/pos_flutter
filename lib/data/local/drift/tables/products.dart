import 'package:drift/drift.dart';

import 'categories.dart';
import 'common_fields.dart';

/// Proyeccion local del producto comercial creado desde Articulos.
/// En este primer alcance solo conserva los datos del alta sencilla.
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

  /// Estrategia de inventario del producto. `direct` permite que una variante
  /// apunte explícitamente a un recurso; no crea ese recurso automáticamente.
  TextColumn get inventoryMode =>
      text().withDefault(const Constant('direct'))();

  @override
  Set<Column> get primaryKey => {id};
}
