import 'package:drift/drift.dart';

import 'common_fields.dart';

/// Catálogo de proveedores comerciales con identidad y trazabilidad propias.
/// Hereda CommonFields; active es estructural y no habilita bajas en esta fase.
/// No hay unicidad de nombre, teléfono ni notas.
@DataClassName('SupplierRow')
class Suppliers extends Table with CommonFields {
  /// Nombre obligatorio normalizado por el contrato de eventos.
  TextColumn get name => text()();

  /// Teléfono opcional como texto, sin interpretar prefijos o ceros iniciales.
  TextColumn get phone => text().nullable()();

  /// Notas opcionales del proveedor; vacío se normaliza a null en el contrato.
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (length(trim(name, ' ' || char(9) || char(10) || char(13))) > 0)",
  ];
}
