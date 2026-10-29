import 'dart:convert';
import 'package:drift/drift.dart';
import '../../application/sync/payloads/sale_adjustment_payload.dart';
import '../../application/sync/payloads/venta_confirmada_payload.dart';
import '../../domain/repositories/sale_adjustment_repository.dart';
import '../../domain/ventas/adjusted_sale.dart';
import '../../domain/ventas/sale_adjustment_document.dart';
import '../../domain/ventas/sale_adjustment_status.dart';
import '../local/drift/app_database.dart';
import 'confirmed_sale_repository_impl.dart';

class SaleAdjustmentRepositoryImpl implements SaleAdjustmentRepository {
  SaleAdjustmentRepositoryImpl(this.db);
  final AppDatabase db;
  @override
  Stream<List<AdjustedSale>> watchSales() => db
      .select(db.events)
      .join([
        leftOuterJoin(
          db.saleAdjustments,
          db.saleAdjustments.eventId.equalsExp(db.events.eventId),
        ),
        leftOuterJoin(
          db.saleDeliveryIncidents,
          db.saleDeliveryIncidents.loserEventId.equalsExp(db.events.eventId),
        ),
      ])
      .watch()
      .map((rows) {
        final events = rows.map((r) => r.readTable(db.events)).toList();
        final originals = events.where(
          (e) =>
              e.eventType == VentaConfirmadaPayload.eventType &&
              e.applicationStatus == 'applied',
        );
        return originals.map((e) {
          final original = ConfirmedSaleRepositoryImpl.fromEvent(
            SaleAdjustmentDao.event(e),
          );
          final history =
              rows
                  .where(
                    (r) =>
                        r.readTableOrNull(db.saleAdjustments)?.saleId ==
                        e.aggregateId,
                  )
                  .toList()
                ..sort(
                  (a, b) => a
                      .readTable(db.saleAdjustments)
                      .revision
                      .compareTo(b.readTable(db.saleAdjustments).revision),
                );
          var returned = <String, int>{};
          var status = SaleAdjustmentStatus.current;
          var officialStatus = SaleAdjustmentStatus.current;
          final officialReturned = <String, int>{};
          var officialRevision = 0, localRevision = 0;
          final documents = <SaleAdjustmentDocument>[];
          for (final row in history) {
            final a = row.readTable(db.saleAdjustments);
            final p = SaleAdjustmentPayload.fromJson(
              Map<String, Object?>.from(jsonDecode(a.payloadJson) as Map),
            );
            final delivery = row.readTable(db.events).deliveryStatus;
            final official =
                delivery == 'delivered' || delivery == 'not_required';
            if (official) {
              officialRevision = a.revision;
              for (final l in p.lines) {
                officialReturned.update(
                  l.saleItemId,
                  (v) => v + l.quantityAtomic,
                  ifAbsent: () => l.quantityAtomic,
                );
              }
              officialStatus = p.kind == 'void'
                  ? SaleAdjustmentStatus.voided
                  : original.items.every(
                      (l) =>
                          officialReturned[l.id] ==
                          (l.quantity ?? l.measuredQuantityAtomic),
                    )
                  ? SaleAdjustmentStatus.fullyReturned
                  : SaleAdjustmentStatus.partiallyReturned;
            }
            if (a.commercialActive) {
              localRevision = a.revision;
              for (final l in p.lines) {
                returned.update(
                  l.saleItemId,
                  (v) => v + l.quantityAtomic,
                  ifAbsent: () => l.quantityAtomic,
                );
              }
              status = p.kind == 'void'
                  ? SaleAdjustmentStatus.voided
                  : original.items.every(
                      (l) =>
                          returned[l.id] ==
                          (l.quantity ?? l.measuredQuantityAtomic),
                    )
                  ? SaleAdjustmentStatus.fullyReturned
                  : SaleAdjustmentStatus.partiallyReturned;
            }
            documents.add(
              SaleAdjustmentDocument(
                operationId: a.id,
                eventId: a.eventId,
                saleId: a.saleId,
                businessDate: a.businessDate,
                reason: a.reason,
                settlementReference: p.settlement.reference,
                cashSessionId: p.settlement.cash?.sessionId,
                resolutionEventId: row
                    .readTableOrNull(db.saleDeliveryIncidents)
                    ?.resolutionEventId,
                userId: a.userId,
                deviceId: a.deviceId,
                occurredAt: DateTime.fromMillisecondsSinceEpoch(
                  a.occurredAtMs,
                  isUtc: true,
                ),
                amountMinor: a.amountMinor,
                method: a.method,
                settlementAction: a.settlementAction,
                deliveryStatus: row.readTable(db.events).deliveryStatus,
                officialStatus: officialStatus,
                localStatus: status,
                officialRevision: officialRevision,
                localRevision: localRevision,
                incidentId:
                    row
                                .readTableOrNull(db.saleDeliveryIncidents)
                                ?.resolutionEventId ==
                            null &&
                        ['conflict', 'rejected'].contains(delivery)
                    ? a.eventId
                    : null,
                lines: [
                  for (final l in p.lines)
                    (
                      saleItemId: l.saleItemId,
                      quantityAtomic: l.quantityAtomic,
                      amountMinor: l.amountMinor,
                      recoveredCostMinor: l.recoveredCostMinor,
                      destination: l.destination,
                    ),
                ],
                physicalEffectIds: [
                  if (p.settlement.cash != null) p.settlement.cash!.movementId,
                  for (final l in p.lines)
                    for (final m in l.stock) m.movementId,
                ],
              ),
            );
          }
          return AdjustedSale(
            original: original,
            status: status,
            adjustments: documents,
          );
        }).toList()..sort(
          (a, b) => b.original.createdAt.compareTo(a.original.createdAt),
        );
      });
}
