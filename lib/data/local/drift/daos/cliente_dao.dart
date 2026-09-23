part of '../app_database.dart';

@DriftAccessor(tables: [Clientes])
class ClienteDao extends DatabaseAccessor<AppDatabase> with _$ClienteDaoMixin {
  ClienteDao(super.db);

  Stream<List<ClienteRow>> watchClientes() =>
      (select(clientes)..orderBy([
            (t) => OrderingTerm(expression: t.nombre),
            (t) => OrderingTerm(expression: t.id),
          ]))
          .watch();

  Future<ClienteRow?> findById(String id) =>
      (select(clientes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertCliente(ClientesCompanion row) async {
    await into(clientes).insertOnConflictUpdate(row);
  }

  Future<void> advanceServerSequence(String id, int sequence) async {
    await (update(clientes)..where(
          (t) =>
              t.id.equals(id) &
              (t.lastServerSequence.isNull() |
                  t.lastServerSequence.isSmallerThanValue(sequence)),
        ))
        .write(ClientesCompanion(lastServerSequence: Value(sequence)));
  }

  Future<void> deleteCreatedByEvent(String eventId) async {
    final rows = await (select(
      clientes,
    )..where((t) => t.createdEventId.equals(eventId))).get();
    for (final row in rows) {
      final used = await db
          .customSelect(
            'SELECT 1 FROM sales WHERE cliente_id = ? UNION ALL SELECT 1 FROM customer_payments WHERE cliente_id = ? LIMIT 1',
            variables: [Variable(row.id), Variable(row.id)],
          )
          .get();
      if (used.isNotEmpty) {
        await (update(clientes)..where((t) => t.id.equals(row.id))).write(
          const ClientesCompanion(active: Value(false)),
        );
        return;
      }
    }
    await (delete(
      clientes,
    )..where((t) => t.createdEventId.equals(eventId))).go();
  }
}
