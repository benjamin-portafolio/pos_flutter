part of '../app_database.dart';

/// DAO de `financial_categories`: lectura ordenada `(name, id)`, upsert (el
/// oficial reemplaza la alta local, contrato §6.6) y avance de secuencia.
@DriftAccessor(tables: [FinancialCategories])
class FinancialCategoryDao extends DatabaseAccessor<AppDatabase>
    with _$FinancialCategoryDaoMixin {
  FinancialCategoryDao(super.db);

  Stream<List<FinancialCategoryRow>> watchCategories() =>
      (select(financialCategories)
            ..orderBy([
              (t) => OrderingTerm(expression: t.name),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .watch();

  Future<FinancialCategoryRow?> findById(String id) =>
      (select(financialCategories)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(FinancialCategoriesCompanion row) async {
    await into(financialCategories).insertOnConflictUpdate(row);
  }

  Future<void> advanceServerSequence(String id, int sequence) async {
    await (update(financialCategories)
          ..where(
            (t) =>
                t.id.equals(id) &
                (t.lastServerSequence.isNull() |
                    t.lastServerSequence.isSmallerThanValue(sequence)),
          ))
        .write(FinancialCategoriesCompanion(lastServerSequence: Value(sequence)));
  }
}