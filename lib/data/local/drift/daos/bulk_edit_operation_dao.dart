part of '../app_database.dart';

@DriftAccessor(tables: [BulkEditOperations])
class BulkEditOperationDao extends DatabaseAccessor<AppDatabase>
    with _$BulkEditOperationDaoMixin {
  BulkEditOperationDao(super.db);

  Future<BulkEditOperationRow?> buscar(String id) => (select(
    bulkEditOperations,
  )..where((r) => r.operationId.equals(id))).getSingleOrNull();

  Future<List<BulkEditOperationRow>> listar({
    String? batchId,
    bool soloPendientes = false,
  }) =>
      (select(bulkEditOperations)
            ..where(
              (r) =>
                  (batchId == null
                      ? const Constant(true)
                      : r.batchId.equals(batchId)) &
                  (soloPendientes
                      ? r.localState.equals('confirmada')
                      : const Constant(true)),
            )
            ..orderBy([
              (r) => OrderingTerm.asc(r.confirmedAt),
              (r) => OrderingTerm.asc(r.rowId),
            ]))
          .get();

  Future<void> reservar(BulkEditOperationsCompanion row) async {
    await into(bulkEditOperations).insert(row);
  }

  Future<int> completar(String id, String json) =>
      (update(bulkEditOperations)..where(
            (r) => r.operationId.equals(id) & r.localState.equals('confirmada'),
          ))
          .write(
            BulkEditOperationsCompanion(
              localState: const Value('aplicada'),
              resultJson: Value(json),
              finishedAt: Value(DateTime.now().toUtc()),
            ),
          );

  Future<int> cerrarPendientes(String batchId) =>
      (update(bulkEditOperations)..where(
            (r) =>
                r.batchId.equals(batchId) & r.localState.equals('confirmada'),
          ))
          .write(
            BulkEditOperationsCompanion(
              localState: const Value('cerrada'),
              finishedAt: Value(DateTime.now().toUtc()),
            ),
          );
}
