import 'package:drift/drift.dart';

import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/projections/variant_inventory_memory_store.dart';
import 'app_database.dart' as drift;

class DriftVariantInventoryMemoryStore implements VariantInventoryMemoryStore {
  DriftVariantInventoryMemoryStore({
    required drift.VariantInventoryMemoryDao dao,
  }) : _dao = dao;

  final drift.VariantInventoryMemoryDao _dao;

  @override
  Future<VariantInventoryMemoryProjection?> findByVariantId(
    String variantId,
  ) async {
    final row = await _dao.obtenerPorVariante(variantId);
    if (row == null) return null;
    return VariantInventoryMemoryProjection(
      variantId: row.variantId,
      inventoryItemId: row.inventoryItemId,
      sourceEventId: row.sourceEventId,
      sourceServerSequence: row.sourceServerSequence,
    );
  }

  @override
  Future<List<VariantInventoryMemoryProjection>> findByInventoryItemId(
    String inventoryItemId,
  ) async {
    final rows = await _dao.obtenerPorRecurso(inventoryItemId);
    return rows
        .map(
          (row) => VariantInventoryMemoryProjection(
            variantId: row.variantId,
            inventoryItemId: row.inventoryItemId,
            sourceEventId: row.sourceEventId,
            sourceServerSequence: row.sourceServerSequence,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> upsert(
    String variantId,
    String inventoryItemId,
    SyncEvent event,
  ) async {
    await _dao.insertarOActualizar(
      drift.VariantInventoryMemoryCompanion.insert(
        variantId: variantId,
        inventoryItemId: inventoryItemId,
        sourceEventId: event.eventId,
        sourceServerSequence: Value(event.serverSequence),
      ),
    );
  }

  @override
  Future<void> advanceEventServerSequence(String eventId, int serverSequence) =>
      _dao.avanzarSecuenciaEvento(eventId, serverSequence);

  @override
  Future<void> deleteByInventoryItemId(String inventoryItemId) async {
    await _dao.eliminarPorRecurso(inventoryItemId);
  }

  @override
  Future<void> deleteByVariantId(String variantId) async {
    await _dao.eliminarPorVariante(variantId);
  }
}
