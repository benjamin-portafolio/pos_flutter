part of '../app_database.dart';

@DriftAccessor(tables: [VariantInventoryMemory])
class VariantInventoryMemoryDao extends DatabaseAccessor<AppDatabase>
    with _$VariantInventoryMemoryDaoMixin {
  VariantInventoryMemoryDao(super.db);

  Future<VariantInventoryMemoryRow?> obtenerPorVariante(String variantId) {
    return (select(
      variantInventoryMemory,
    )..where((row) => row.variantId.equals(variantId))).getSingleOrNull();
  }

  Future<List<VariantInventoryMemoryRow>> obtenerPorRecurso(
    String inventoryItemId,
  ) {
    return (select(
      variantInventoryMemory,
    )..where((row) => row.inventoryItemId.equals(inventoryItemId))).get();
  }

  Future<void> insertarOActualizar(
    VariantInventoryMemoryCompanion companion,
  ) async {
    await into(variantInventoryMemory).insertOnConflictUpdate(companion);
  }

  Future<void> avanzarSecuenciaEvento(String eventId, int sequence) =>
      db.transaction(() => _avanzarSecuenciaEvento(eventId, sequence));

  Future<void> _avanzarSecuenciaEvento(String eventId, int sequence) async {
    await (update(variantInventoryMemory)..where(
          (m) =>
              m.sourceEventId.equals(eventId) &
              (m.sourceServerSequence.isNull() |
                  m.sourceServerSequence.isSmallerThanValue(sequence)),
        ))
        .write(
          VariantInventoryMemoryCompanion(
            sourceServerSequence: Value(sequence),
          ),
        );
    for (final backup in await select(db.productUpdateUndo).get()) {
      final memories = jsonDecode(backup.memoryJson) as List;
      var changed = false;
      for (final m in memories) {
        if (m['source_event_id'] == eventId &&
            (m['source_server_sequence'] == null ||
                (m['source_server_sequence'] as int) < sequence)) {
          m['source_server_sequence'] = sequence;
          changed = true;
        }
      }
      if (changed) {
        await (update(
          db.productUpdateUndo,
        )..where((b) => b.eventId.equals(backup.eventId))).write(
          ProductUpdateUndoCompanion(memoryJson: Value(jsonEncode(memories))),
        );
      }
    }
  }

  Future<void> eliminarPorVariante(String variantId) async {
    await (delete(
      variantInventoryMemory,
    )..where((row) => row.variantId.equals(variantId))).go();
  }

  Future<void> eliminarPorRecurso(String inventoryItemId) async {
    await (delete(
      variantInventoryMemory,
    )..where((row) => row.inventoryItemId.equals(inventoryItemId))).go();
  }
}
