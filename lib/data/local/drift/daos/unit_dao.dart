part of '../app_database.dart';

@DriftAccessor(tables: [Units])
class UnitDao extends DatabaseAccessor<AppDatabase> with _$UnitDaoMixin {
  UnitDao(super.db);

  Future<List<UnitRow>> obtenerUnidadesActivas() {
    return (select(units)
          ..where((unit) => unit.active.equals(true))
          ..orderBy([
            (unit) => OrderingTerm(
              expression: CustomExpression<int>(
                "CASE dimension WHEN 'count' THEN 0 WHEN 'mass' THEN 1 ELSE 2 END",
              ),
            ),
            (unit) => OrderingTerm(expression: unit.atomicFactor),
            (unit) => OrderingTerm(expression: unit.name),
          ]))
        .get();
  }

  Future<UnitRow?> obtenerUnidadPorId(String unitId) {
    return (select(
      units,
    )..where((unit) => unit.unitId.equals(unitId))).getSingleOrNull();
  }
}
