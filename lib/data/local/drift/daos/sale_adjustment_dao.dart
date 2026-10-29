part of '../app_database.dart';

/// Acceso al diario inmutable y sus líneas; las escrituras usan transacción.
@DriftAccessor(tables: [SaleAdjustments, SaleAdjustmentLines])
class SaleAdjustmentDao extends DatabaseAccessor<AppDatabase>
    with _$SaleAdjustmentDaoMixin {
  SaleAdjustmentDao(super.db);

  static SyncEvent event(EventRecord e) => SyncEvent(
    eventId: e.eventId,
    aggregateType: e.aggregateType,
    aggregateId: e.aggregateId,
    eventType: e.eventType,
    deviceId: e.deviceId,
    userId: e.userId,
    createdAtLocal: SaleAdjustmentSyncContract.supports(e.eventType)
        ? DateTime.fromMillisecondsSinceEpoch(
            SaleAdjustmentSyncContract.occurredAt(
              e.eventType,
              Map<String, Object?>.from(jsonDecode(e.payload) as Map),
            ),
            isUtc: true,
          )
        : e.createdAtLocal,
    baseVersion: e.baseVersion,
    baseServerSequence: e.baseServerSequence,
    serverSequence: e.serverSequence,
    applicationStatus: e.applicationStatus,
    deliveryStatus: e.deliveryStatus,
    rejectionReason: e.rejectionReason,
    payload: Map<String, Object?>.from(jsonDecode(e.payload) as Map),
  );

  Future<List<SaleAdjustmentRow>> forSale(String saleId) =>
      (db.select(db.saleAdjustments)
            ..where((t) => t.saleId.equals(saleId))
            ..orderBy([(t) => OrderingTerm.asc(t.revision)]))
          .get();

  Future<void> insert(SyncEvent e, SaleAdjustmentPayload p) async {
    await db
        .into(db.saleAdjustments)
        .insert(
          SaleAdjustmentsCompanion.insert(
            id: p.operationId,
            saleId: p.saleId,
            eventId: e.eventId,
            confirmationEventId: p.confirmationEventId,
            baseEventId: p.previousAdjustmentEventId ?? p.confirmationEventId,
            kind: p.kind,
            revision: p.expectedRevision + 1,
            businessDate: p.businessDate,
            occurredAtMs: p.occurredAtMs,
            utcOffsetMinutes: p.utcOffsetMinutes,
            reason: p.reason,
            userId: e.userId,
            deviceId: e.deviceId,
            amountMinor: p.totalMinor,
            method: p.settlement.method,
            salePaymentId: Value(p.settlement.paymentId),
            clienteId: Value(p.settlement.clienteId),
            currency: p.currency,
            settlementReference: Value(p.settlement.reference),
            cashEnabled: p.settlement.cashEnabled,
            settlementAction: p.settlement.action,
            payloadJson: jsonEncode(p.toJson()),
            createdEventId: Value(e.eventId),
            lastEventId: Value(e.eventId),
            lastServerSequence: Value(e.serverSequence),
          ),
        );
    for (final l in p.lines) {
      await db
          .into(db.saleAdjustmentLines)
          .insert(
            SaleAdjustmentLinesCompanion.insert(
              operationId: p.operationId,
              saleItemId: l.saleItemId,
              quantityAtomic: l.quantityAtomic,
              amountMinor: l.amountMinor,
              recoveredCostMinor: Value(l.recoveredCostMinor),
              destination: l.destination,
              reason: Value(l.reason),
            ),
          );
    }
  }
}
