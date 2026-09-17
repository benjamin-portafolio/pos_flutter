import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/payloads/venta_confirmada_payload.dart';
import '../../../application/sync/projections/confirmed_sale_store.dart';
import '../../../application/sync/projections/sale_projection.dart';
import '../../../application/sync/projections/sale_item_projection.dart';
import '../../../domain/ventas/sale_status.dart';
import 'app_database.dart';

class DriftConfirmedSaleStore implements ConfirmedSaleStore {
  DriftConfirmedSaleStore(this.db);
  final AppDatabase db;
  @override
  Future<void> apply(SyncEvent event, VentaConfirmadaPayload p) =>
      db.transaction(() async {
        final sale = await db.saleDao.findById(event.aggregateId);
        if (sale?.status == SaleStatus.confirmada) {
          if (sale!.lastEventId == event.eventId) {
            return;
          }
          throw StateError('Esta venta ya fue cobrada.');
        }
        if (sale != null &&
            (sale.status != SaleStatus.borrador ||
                sale.userId != event.userId ||
                sale.deviceId != event.deviceId)) {
          throw StateError('Identidad de venta ocupada.');
        }
        // La FK exige que incluso una variante histórica siga existiendo.
        await db.saleDao.saveSale(
          SaleProjection(
            id: event.aggregateId,
            active: true,
            version: 1,
            createdEventId: event.eventId,
            lastEventId: event.eventId,
            lastServerSequence: event.serverSequence,
            userId: event.userId,
            deviceId: event.deviceId,
            status: SaleStatus.confirmada,
            totalMinor: p.totalMinor,
            createdAtLocal: sale?.createdAtLocal ?? event.createdAtLocal,
            updatedAtLocal: event.createdAtLocal,
          ),
        );
        final existing = await db.saleDao.items(event.aggregateId);
        if (existing.any((item) => !p.lines.any((line) => line.id == item.id))) {
          throw StateError('Líneas inconsistentes.');
        }
        for (var i = 0; i < p.lines.length; i++) {
          final line = p.lines[i];
          final occupied = await (db.select(
            db.saleItems,
          )..where((t) => t.id.equals(line.id))).getSingleOrNull();
          if (occupied != null && occupied.saleId != event.aggregateId) {
            throw StateError('Identidad de línea ocupada.');
          }
          await db.saleDao.saveItem(
            SaleItemProjection(
              id: line.id,
              active: true,
              version: 1,
              createdEventId: event.eventId,
              lastEventId: event.eventId,
              lastServerSequence: event.serverSequence,
              saleId: event.aggregateId,
              sortOrder: i,
              snapshot: line.snapshot,
            ),
          );
        }
        await db
            .into(db.salePayments)
            .insert(
              SalePaymentsCompanion.insert(
                id: p.paymentId,
                saleId: event.aggregateId,
                amountMinor: p.totalMinor,
                receivedMinor: p.receivedMinor,
                changeMinor: p.changeMinor,
                currency: p.currency,
                createdEventId: Value(event.eventId),
                lastEventId: Value(event.eventId),
                lastServerSequence: Value(event.serverSequence),
              ),
            );
        for (final line in p.lines) {
          for (final c in line.consumptions) {
            if (c.movementId == null) continue;
            final balance =
                await (db.select(db.inventoryBalances)..where(
                      (b) => b.inventoryItemId.equals(c.inventoryItemId),
                    ))
                    .getSingle();
            int next(int n) {
              final value = BigInt.from(n) + BigInt.from(c.deltaAtomic);
              if (value.abs() > BigInt.from(9007199254740991)) {
                throw StateError('Saldo fuera de rango.');
              }
              return value.toInt();
            }

            final onHand = next(balance.quantityOnHandAtomic);
            final available = next(balance.quantityAvailableAtomic);
            await db
                .into(db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion.insert(
                    movementId: c.movementId!,
                    inventoryItemId: c.inventoryItemId,
                    saleItemId: Value(line.id),
                    eventId: event.eventId,
                    movementType: 'sale_consumption',
                    quantityDeltaAtomic: c.deltaAtomic,
                    createdAtLocal: event.createdAtLocal,
                    serverSequence: Value(event.serverSequence),
                  ),
                );
            await (db.update(
              db.inventoryBalances,
            )..where((b) => b.inventoryItemId.equals(c.inventoryItemId))).write(
              InventoryBalancesCompanion(
                quantityOnHandAtomic: Value(onHand),
                quantityAvailableAtomic: Value(available),
                version: Value(balance.version + 1),
                lastEventId: Value(event.eventId),
                lastServerSequence: Value(
                  event.serverSequence ?? balance.lastServerSequence,
                ),
              ),
            );
          }
        }
      });
  @override
  Future<void> acknowledge(String eventId, int serverSequence) =>
      db.transaction(() async {
        await (db.update(db.sales)..where((t) => t.lastEventId.equals(eventId)))
            .write(SalesCompanion(lastServerSequence: Value(serverSequence)));
        await (db.update(
          db.saleItems,
        )..where((t) => t.lastEventId.equals(eventId))).write(
          SaleItemsCompanion(lastServerSequence: Value(serverSequence)),
        );
        await (db.update(
          db.salePayments,
        )..where((t) => t.lastEventId.equals(eventId))).write(
          SalePaymentsCompanion(lastServerSequence: Value(serverSequence)),
        );
        await (db.update(
          db.inventoryMovements,
        )..where((t) => t.eventId.equals(eventId))).write(
          InventoryMovementsCompanion(serverSequence: Value(serverSequence)),
        );
        await (db.update(
          db.inventoryBalances,
        )..where((t) => t.lastEventId.equals(eventId))).write(
          InventoryBalancesCompanion(lastServerSequence: Value(serverSequence)),
        );
      });
  @override
  Stream<List<SyncEvent>> watchConfirmed() =>
      (db.select(db.events)
            ..where(
              (e) =>
                  e.eventType.equals(VentaConfirmadaPayload.eventType) &
                  e.applicationStatus.equals('applied'),
            )
            ..orderBy([(e) => OrderingTerm.desc(e.createdAtLocal)]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (e) => SyncEvent(
                    eventId: e.eventId,
                    aggregateType: e.aggregateType,
                    aggregateId: e.aggregateId,
                    eventType: e.eventType,
                    deviceId: e.deviceId,
                    userId: e.userId,
                    createdAtLocal: e.createdAtLocal,
                    payload: Map<String, Object?>.from(
                      jsonDecode(e.payload) as Map,
                    ),
                    deliveryStatus: e.deliveryStatus,
                    rejectionReason: e.rejectionReason,
                    serverSequence: e.serverSequence,
                  ),
                )
                .toList(),
          );
}
