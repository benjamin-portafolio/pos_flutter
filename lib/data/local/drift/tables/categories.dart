import 'package:drift/drift.dart';

import 'common_fields.dart';

/// Proyeccion local de las categorias usadas para organizar los articulos.
/// Hereda `active` de [CommonFields] por uniformidad estructural, pero este
/// agregado no usa el campo para filtrar ni exponer un ciclo de vida.
@DataClassName('CategoryRow')
class Categories extends Table with CommonFields {
  /// Nombre visible de la categoria en la gestion de inventario y articulos.
  TextColumn get name => text()();

  /// Clave estable del color que la interfaz usara para representar la categoria.
  TextColumn get colorKey => text().withDefault(const Constant('neutral'))();

  /// Posicion opcional de la categoria en los listados.
  /// Las categorias sin posicion explicita aparecen al final.
  IntColumn get sortOrder => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
