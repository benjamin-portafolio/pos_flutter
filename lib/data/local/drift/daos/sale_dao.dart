part of '../app_database.dart';

/// Adaptador de las proyecciones de captura, con acceso transaccional a SQLite.
@DriftAccessor(tables: [Sales, SaleItems])
class SaleDao extends DatabaseAccessor<AppDatabase>
    with _$SaleDaoMixin
    implements SaleDraftProjectionStore {
  SaleDao(super.db);
  @override
  Future<T> atomic<T>(Future<T> Function() action) => transaction(action);
  @override
  Future<SaleProjection?> findDraft(String userId, String deviceId) async {
    final row =
        await (select(sales)..where(
              (t) =>
                  t.userId.equals(userId) &
                  t.deviceId.equals(deviceId) &
                  t.active.equals(true) &
                  t.status.equals('borrador'),
            ))
            .getSingleOrNull();
    return row == null ? null : _sale(row);
  }

  @override
  Future<SaleProjection?> findById(String id) async {
    final row = await (select(
      sales,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _sale(row);
  }

  SaleProjection _sale(SaleRow row) => SaleProjection(
    id: row.id,
    active: row.active,
    version: row.version,
    createdEventId: row.createdEventId,
    lastEventId: row.lastEventId,
    lastServerSequence: row.lastServerSequence,
    userId: row.userId,
    deviceId: row.deviceId,
    status: SaleStatus.values.byName(row.status),
    totalMinor: row.totalMinor,
    createdAtLocal: row.createdAtLocal,
    updatedAtLocal: row.updatedAtLocal,
  );
  @override
  Future<List<SaleItemProjection>> items(String saleId) async {
    final rows =
        await (select(saleItems)
              ..where((t) => t.saleId.equals(saleId))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get();
    return rows
        .map(
          (r) => SaleItemProjection(
            id: r.id,
            active: r.active,
            version: r.version,
            createdEventId: r.createdEventId,
            lastEventId: r.lastEventId,
            lastServerSequence: r.lastServerSequence,
            saleId: r.saleId,
            sortOrder: r.sortOrder,
            snapshot: SaleItemSnapshot(
              variantId: r.variantId,
              productName: r.productNameSnapshot,
              variantName: r.variantNameSnapshot,
              saleMode: r.saleModeSnapshot,
              quantity: r.quantity,
              measuredQuantityAtomic: r.measuredQuantityAtomic,
              unitPriceMinor: r.unitPriceMinor,
              standardCostMinor: r.standardCostMinorSnapshot,
              priceReferenceQuantityAtomic:
                  r.priceReferenceQuantityAtomicSnapshot,
              unitCode: r.saleUnitCodeSnapshot,
              unitSymbol: r.saleUnitSymbolSnapshot,
              unitAtomicFactor: r.saleUnitAtomicFactorSnapshot,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<void> saveSale(SaleProjection s) async {
    await into(sales).insertOnConflictUpdate(
      SalesCompanion.insert(
        id: s.id,
        userId: s.userId,
        deviceId: s.deviceId,
        status: Value(s.status.name),
        totalMinor: s.totalMinor,
        createdAtLocal: s.createdAtLocal,
        updatedAtLocal: s.updatedAtLocal,
        active: Value(s.active),
        version: Value(s.version),
        createdEventId: Value(s.createdEventId),
        lastEventId: Value(s.lastEventId),
        lastServerSequence: Value(s.lastServerSequence),
      ),
    );
  }

  @override
  Future<void> saveItem(SaleItemProjection p) async {
    final s = p.snapshot;
    await into(saleItems).insertOnConflictUpdate(
      SaleItemsCompanion.insert(
        id: p.id,
        saleId: p.saleId,
        variantId: s.variantId,
        productNameSnapshot: s.productName,
        variantNameSnapshot: Value(s.variantName),
        saleModeSnapshot: s.saleMode,
        quantity: Value(s.quantity),
        measuredQuantityAtomic: Value(s.measuredQuantityAtomic),
        unitPriceMinor: s.unitPriceMinor,
        standardCostMinorSnapshot: Value(s.standardCostMinor),
        priceReferenceQuantityAtomicSnapshot: Value(
          s.priceReferenceQuantityAtomic,
        ),
        saleUnitCodeSnapshot: Value(s.unitCode),
        saleUnitSymbolSnapshot: Value(s.unitSymbol),
        saleUnitAtomicFactorSnapshot: Value(s.unitAtomicFactor),
        totalMinor: s.totalMinor,
        sortOrder: p.sortOrder,
        active: Value(p.active),
        version: Value(p.version),
        createdEventId: Value(p.createdEventId),
        lastEventId: Value(p.lastEventId),
        lastServerSequence: Value(p.lastServerSequence),
      ),
    );
  }
}
