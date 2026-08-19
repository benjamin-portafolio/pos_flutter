import 'package:drift/drift.dart';

/// Catálogo estable de unidades usadas para capturar y mostrar inventario.
/// Es dato de referencia compartido con PostgreSQL, no una proyección de evento,
/// por lo que deliberadamente no hereda `CommonFields`.
@DataClassName('UnitRow')
class Units extends Table {
  /// UUID estable e idéntico en cada dispositivo y en el servidor.
  TextColumn get unitId => text()();

  /// Código estable usado por migraciones y reglas de interoperabilidad.
  TextColumn get code => text().unique()();

  /// Nombre localizado que se muestra al usuario.
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// Abreviatura visible junto a las cantidades.
  TextColumn get symbol => text().withLength(min: 1, max: 16)();

  /// Dimensión física: `count`, `mass` o `volume`.
  TextColumn get dimension => text().customConstraint(
    "NOT NULL CHECK (dimension IN ('count', 'mass', 'volume'))",
  )();

  /// Número de átomos de la dimensión representados por una unidad.
  IntColumn get atomicFactor =>
      integer().customConstraint('NOT NULL CHECK (atomic_factor > 0)')();

  /// Máximo de decimales aceptados al capturar cantidades en esta unidad.
  IntColumn get maxFractionDigits => integer().customConstraint(
    'NOT NULL CHECK (max_fraction_digits >= 0 AND max_fraction_digits <= 9)',
  )();

  /// Determina si la unidad puede seleccionarse en nuevas operaciones.
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {unitId};
}
