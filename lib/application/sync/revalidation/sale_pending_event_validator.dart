import '../payloads/abono_cliente_registrado_payload.dart';
import '../models/sync_event.dart';
import '../payloads/venta_confirmada_payload.dart';
import '../synced_event_history.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';

class SalePendingEventValidator implements PendingEventValidator {
  SalePendingEventValidator(this.history);
  final SyncedEventHistory history;
  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    final dependencies =
        event.eventType == AbonoClienteRegistradoPayload.eventType
        ? AbonoClienteRegistradoPayload.fromJson(
            event.payload,
          ).dependencyEventIds
        : VentaConfirmadaPayload.fromJson(event.payload).dependencyEventIds;
    for (final id in dependencies) {
      final dependency = await history.eventById(id);
      if (dependency == null ||
          conflictedEventIds.contains(id) ||
          dependency.deliveryStatus == 'conflict' ||
          dependency.deliveryStatus == 'rejected' ||
          dependency.deliveryStatus == 'not_required') {
        return const PendingConflict(
          'Operación registrada: una dependencia no se puede sincronizar. Requiere atención.',
        );
      }
    }
    return null;
  }

  // Un cobro nunca se deshace por un problema de entrega.
  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {}
}
