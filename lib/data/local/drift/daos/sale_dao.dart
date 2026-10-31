part of '../app_database.dart';

/// Adaptador de las proyecciones de captura, con acceso transaccional a SQLite.
@DriftAccessor(tables: [Sales, SaleItems])
class SaleDao extends DatabaseAccessor<AppDatabase>
    with _$SaleDaoMixin
    implements SaleDraftProjectionStore, AppliedLocalEventReader {
  @override
  Future<SyncEvent?> appliedLocalEvent(String operationId) async {
    final row = await db.eventDao.obtenerEventoPorId(operationId);
    if (row == null || row.applicationStatus != 'applied') return null;
    return SyncEvent(
      eventId: row.eventId,
      aggregateType: row.aggregateType,
      aggregateId: row.aggregateId,
      eventType: row.eventType,
      deviceId: row.deviceId,
      userId: row.userId,
      baseVersion: row.baseVersion,
      createdAtLocal: row.createdAtLocal,
      deliveryStatus: row.deliveryStatus,
      payload: Map<String, Object?>.from(jsonDecode(row.payload) as Map),
    );
  }

  SaleDao(super.db);

  /// Una sola consulta observa cabecera y líneas de forma consistente.
  Stream<List<({SaleRow sale, SaleItemRow? item})>> watchDraft(
    String userId,
    String deviceId,
  ) {
    final query =
        select(sales).join([
            leftOuterJoin(
              saleItems,
              saleItems.saleId.equalsExp(sales.id) &
                  saleItems.active.equals(true),
            ),
          ])
          ..where(
            sales.userId.equals(userId) &
                sales.deviceId.equals(deviceId) &
                sales.active.equals(true) &
                sales.status.equals(SaleStatus.borrador.name),
          )
          ..orderBy([
            OrderingTerm.asc(sales.createdAtLocal),
            OrderingTerm.asc(sales.id),
            OrderingTerm.asc(saleItems.sortOrder),
          ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (sale: row.readTable(sales), item: row.readTableOrNull(saleItems)),
      ],
    );
  }

  @override
  Future<bool> wasCleared(String saleId) async =>
      await (select(db.events)
            ..where(
              (t) =>
                  t.aggregateId.equals(saleId) &
                  t.aggregateType.equals(
                    VentaBorradorLimpiadaPayload.aggregateType,
                  ) &
                  t.eventType.equals(VentaBorradorLimpiadaPayload.eventType) &
                  t.applicationStatus.equals('applied'),
            )
            ..limit(1))
          .getSingleOrNull() !=
      null;

  @override
  Future<void> deleteDraft(String saleId) => transaction(() async {
    await (delete(saleItems)..where((t) => t.saleId.equals(saleId))).go();
    await (delete(sales)..where((t) => t.id.equals(saleId))).go();
  });

  @override
  Future<void> deleteItem(String saleId, String saleItemId) async {
    await (delete(
      saleItems,
    )..where((t) => t.saleId.equals(saleId) & t.id.equals(saleItemId))).go();
  }

  @override
  Future<T> atomic<T>(Future<T> Function() action) => transaction(action);
  @override
  Future<SaleProjection?> findDraft(String userId, String deviceId) async {
    final row =
        await (select(sales)
              ..where(
                (t) =>
                    t.userId.equals(userId) &
                    t.deviceId.equals(deviceId) &
                    t.active.equals(true) &
                    t.status.equals('borrador'),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAtLocal),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(1))
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
    pricingContractVersion: row.pricingContractVersion,
    pricingMode: row.pricingMode,
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
            persistedTotalMinor: r.totalMinor,
            snapshot: SaleItemSnapshot(
              variantId: r.variantId,
              priceSnapshotVersion: r.priceSnapshotVersion,
              normalPriceMinorSnapshot: r.normalPriceMinorSnapshot,
              offerPriceMinorSnapshot: r.offerPriceMinorSnapshot,
              effectivePriceSource: r.effectivePriceSource,
              priceSelection: r.priceSelection,
              priceConfigurationEventId: r.priceConfigurationEventId,

              consumptionConfigurationKey: r.consumptionConfigurationKey,
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
    await into(sales).insertOnConflictUpdate(_saleCompanion(s));
  }

  SalesCompanion _saleCompanion(SaleProjection s) => SalesCompanion.insert(
    id: s.id,
    userId: s.userId,
    pricingContractVersion: Value(s.pricingContractVersion),
    pricingMode: Value(s.pricingMode),
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
  );

  @override
  Future<void> saveItem(SaleItemProjection p) async {
    await into(saleItems).insertOnConflictUpdate(_itemCompanion(p));
  }

  SaleItemsCompanion _itemCompanion(SaleItemProjection p) {
    final s = p.snapshot;
    return SaleItemsCompanion.insert(
      id: p.id,
      saleId: p.saleId,
      variantId: s.variantId,
      priceSnapshotVersion: Value(s.priceSnapshotVersion),
      normalPriceMinorSnapshot: Value(s.normalPriceMinorSnapshot),
      offerPriceMinorSnapshot: Value(s.offerPriceMinorSnapshot),
      effectivePriceSource: Value(s.effectivePriceSource),
      priceSelection: Value(s.priceSelection),
      priceConfigurationEventId: Value(s.priceConfigurationEventId),

      consumptionConfigurationKey: Value(s.consumptionConfigurationKey),
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
    );
  }
}
