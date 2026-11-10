import 'recovery_reconciliation_validator.dart';
import 'recovery_snapshot.dart';

/// La conciliación entregada acredita la presencia física del saldo sin volver
/// a ejecutar su efecto. El enlace local original se conserva en el sidecar.
class RecoveryPhysicalProvenance {
  static Map<String, Object?>? balanceEvent(
    RecoverySnapshot snapshot,
    Map<String, Object?> balance,
  ) {
    final id = balance['last_event_id'] as String;
    final event = snapshot.event(id);
    if (event == null || event['delivery_status'] == 'delivered') return event;
    if (!['rejected', 'conflict'].contains(event['delivery_status'])) {
      return null;
    }
    final incidents = snapshot
        .relatedRows('sale_delivery_incidents', 'loser_event_id', id)
        .toList();
    if (incidents.length != 1 ||
        incidents.single['resolution_event_id'] == null) {
      return null;
    }
    RecoveryReconciliationValidator.validateIncident(
      snapshot,
      incidents.single,
    );
    final resolution = incidents.single['resolution_event_id'] as String;
    final ownsStock = snapshot
        .relatedRows('sale_reconciliation_effects', 'event_id', resolution)
        .any(
          (e) =>
              e['ledger'] == 'stock' &&
              e['target_id'] == balance['inventory_item_id'],
        );
    if (!ownsStock) return null;
    return snapshot.event(resolution);
  }
}
