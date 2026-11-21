import '../payloads/supplier_replenishment_patch.dart';

abstract interface class ReplenishmentProjectionStore {
  Future<void> applyReplenishment(
    String variantId,
    SupplierReplenishmentPatch patch,
  );
}
