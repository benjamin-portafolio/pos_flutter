import '../models/sync_event.dart';

abstract interface class VariantInventoryMemoryStore {
  Future<VariantInventoryMemoryProjection?> findByVariantId(String variantId);

  Future<List<VariantInventoryMemoryProjection>> findByInventoryItemId(
    String inventoryItemId,
  );

  Future<void> upsert(
    String variantId,
    String inventoryItemId,
    SyncEvent event,
  );

  Future<void> advanceEventServerSequence(String eventId, int serverSequence);

  Future<void> deleteByInventoryItemId(String inventoryItemId);

  Future<void> deleteByVariantId(String variantId);
}

class VariantInventoryMemoryProjection {
  const VariantInventoryMemoryProjection({
    required this.variantId,
    required this.inventoryItemId,
    required this.sourceEventId,
    required this.sourceServerSequence,
  });

  final String variantId;
  final String inventoryItemId;
  final String sourceEventId;
  final int? sourceServerSequence;
}
