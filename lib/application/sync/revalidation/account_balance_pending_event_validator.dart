import '../models/sync_event.dart';
import '../projections/account_balance_baseline_projection_store.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';

/// Revalida una declaración de saldo inicial que quedó pendiente.
///
/// A diferencia de `CashPendingEventValidator` no recorre `dependencyEventIds`:
/// el hecho no tiene dependencias, no hay nada previo que pueda faltar. Lo que
/// sí puede volverse insatisfacible es el slot único: si otra terminal declaró
/// el saldo mientras esta declaración esperaba, el servidor la va a rechazar y
/// aquí se marca para revisión en vez de enviarla a perder.
class AccountBalancePendingEventValidator implements PendingEventValidator {
  AccountBalancePendingEventValidator(this.store);
  final AccountBalanceBaselineProjectionStore? store;

  @override
  Future<PendingConflict?> validate(
    SyncEvent e,
    Set<String> conflictedEventIds,
  ) async {
    final baseline = await store?.find(e.aggregateId);
    if (baseline != null && baseline.createdEventId != e.eventId) {
      return const PendingConflict(
        'Identidad del saldo inicial en conflicto.',
      );
    }
    final declared = await store?.otherThan(e.eventId);
    if (declared != null) {
      return const PendingConflict(
        'El saldo inicial ya fue declarado en otra terminal: la declaración '
        'pendiente requiere revisión.',
      );
    }
    return null;
  }

  /// Un conflicto de entrega nunca borra ni reabre el hecho declarado.
  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {}
}
