part of '../app_database.dart';

@DriftAccessor(tables: [Clientes])
class ClienteDao extends DatabaseAccessor<AppDatabase> with _$ClienteDaoMixin {
  ClienteDao(super.db);

  Stream<List<ClienteRow>> watchClientes() =>
      (select(clientes)
            ..where((t) => t.active.equals(true))
            ..orderBy([
              (t) => OrderingTerm(expression: t.nombre),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .watch();

  Future<ClienteRow?> findById(String id) =>
      (select(clientes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertCliente(ClientesCompanion row) async {
    await into(clientes).insert(row);
  }

  Future<void> advanceServerSequence(
    String id,
    String eventId,
    int sequence,
  ) async {
    await (update(clientes)..where(
          (t) =>
              t.id.equals(id) &
              t.createdEventId.equals(eventId) &
              (t.lastServerSequence.isNull() |
                  t.lastServerSequence.isSmallerThanValue(sequence)),
        ))
        .write(ClientesCompanion(lastServerSequence: Value(sequence)));
  }

  Future<void> deleteCreatedByEvent(String eventId) async {
    await (delete(
      clientes,
    )..where((t) => t.createdEventId.equals(eventId))).go();
  }
}
