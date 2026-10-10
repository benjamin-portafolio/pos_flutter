part of '../app_database.dart';

@DriftAccessor(tables: [Suppliers])
class ProveedorDao extends DatabaseAccessor<AppDatabase>
    with _$ProveedorDaoMixin {
  ProveedorDao(super.db);

  Stream<List<SupplierRow>> watchProveedores() =>
      (select(suppliers)..orderBy([
            (t) => OrderingTerm(expression: t.name),
            (t) => OrderingTerm(expression: t.id),
          ]))
          .watch();

  Future<SupplierRow?> findById(String id) =>
      (select(suppliers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> save(SuppliersCompanion row) async {
    await into(suppliers).insertOnConflictUpdate(row);
  }
}
