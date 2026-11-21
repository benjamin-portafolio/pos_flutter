import '../models/sync_event.dart';
import '../supplier_order_operation.dart';
import '../projections/supplier_order_projection_store.dart';
import '../synced_event_history.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';
import 'pending_event_dependency_resolver.dart';

class SupplierOrderPendingValidator implements PendingEventValidator {
  SupplierOrderPendingValidator(this.store, this.history);
  final SupplierOrderProjectionStore store;
  final SyncedEventHistory history;
  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    final op = SupplierOrderOperation.decode(event);
    final baseId = op.baseEventId;
    final current = await store.find(op.orderId);
    if (current == null) {
      return const PendingConflict('El pedido ya no está disponible.');
    }
    if (baseId == null) {
      return current.createdEventId != event.eventId
          ? const PendingConflict('Identidad del pedido ocupada.')
          : null;
    }
    final deps = PendingEventDependencyResolver(history);
    if (conflictedEventIds.contains(baseId) || await deps.hasFailed(baseId)) {
      return const PendingConflict('La base del pedido fue rechazada.');
    }
    final base = await deps.resolveBase(
      baseEventId: baseId,
      fallbackServerSequence: event.baseServerSequence,
    );
    if (!base.waitsForLocalDependency && base.serverSequence != null) {
      final official = await history.eventsForAggregateAfter(
        aggregateType: 'supplier_order',
        aggregateId: op.orderId,
        serverSequence: base.serverSequence!,
      );
      if (official.any((e) => e.eventId != event.eventId)) {
        return const PendingConflict('El pedido cambió oficialmente.');
      }
    }
    return null;
  }

  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) =>
      store.restore(event);
}
