part of '../app_database.dart';

/// DAO de `financial_entries`: alta por upsert (idempotente por
/// `created_event_id`) y avance de secuencia por `created_event_id` (eco,
/// contrato §7.1). Sin borrado: la FK RESTRICT y la política de dinero
/// conservan los registros ante incidencias de entrega.
@DriftAccessor(tables: [FinancialEntries])
class FinancialEntryDao extends DatabaseAccessor<AppDatabase>
    with _$FinancialEntryDaoMixin {
  FinancialEntryDao(super.db);

  Future<FinancialEntryRow?> findById(String id) =>
      (select(financialEntries)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(FinancialEntriesCompanion row) async {
    await into(financialEntries).insertOnConflictUpdate(row);
  }

  Future<void> advanceServerSequence(String eventId, int sequence) async {
    await (update(financialEntries)
          ..where(
            (t) =>
                t.createdEventId.equals(eventId) &
                (t.lastServerSequence.isNull() |
                    t.lastServerSequence.isSmallerThanValue(sequence)),
          ))
        .write(FinancialEntriesCompanion(lastServerSequence: Value(sequence)));
  }
}