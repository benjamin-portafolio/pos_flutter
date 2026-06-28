import 'package:drift/drift.dart';

import '../../../../domain/espacios/visibilidad_espacio.dart';
import 'common_fields.dart';

/// Table definition for Espacios (Spaces) in the POS synchronization model.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_espacios_identificacion_unique '
  'ON espacios (identificacion) '
  "WHERE identificacion IS NOT NULL AND identificacion != ''",
)
@DataClassName('Espacio')
class Espacios extends Table with CommonFields {
  @override
  Set<Column> get primaryKey => {id};

  /// Nombre legible del espacio (ej. 'Terraza', 'Bar')
  TextColumn get nombre => text()();

  /// Identificador único provisto por el usuario para fines de negocio (ej. 'piso_1')
  TextColumn get identificacion => text().nullable()();

  /// Nivel de visibilidad/restricción de artículos en este espacio
  IntColumn get visibilidad => intEnum<VisibilidadEspacio>()();
}
