import 'package:drift/drift.dart';

import 'common_fields.dart';

/// Proyeccion local de las categorias usadas para organizar los articulos.
@DataClassName('CategoryRow')
class Categories extends Table with CommonFields {
  /// Nombre visible de la categoria en la gestion de inventario y articulos.
  TextColumn get name => text()();

  /// Clave estable del color que la interfaz usara para representar la categoria.
  TextColumn get colorKey => text().withDefault(const Constant('neutral'))();

  /// Posicion de la categoria en los listados; los valores menores aparecen primero.
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
