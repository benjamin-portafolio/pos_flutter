import '../sale_adjustment_availability.dart';
import '../../config/app_config.dart';
import '../../config/app_config_controller.dart';
import '../../commands/ventas/sale_reconciliation_command_service.dart';
import '../../commands/ventas/sale_adjustment_command_contract.dart';
import '../models/sync_event.dart';
import '../payloads/operacion_venta_conciliada_payload.dart';
import '../projections/sale_reconciliation_store.dart';

class SaleReconciliationEventHandler {
  SaleReconciliationEventHandler({
    required this.store,
    required this.config,
    this.isolatedSyncHarness = false,
    this.availability,
  });
  final SaleReconciliationStore store;
  final AppConfigController config;
  final bool isolatedSyncHarness;
  final SaleAdjustmentAvailability? availability;
  Future<void> apply(SyncEvent e) => store.atomic(() async {
    if (!(e.deliveryStatus == 'delivered' && e.serverSequence != null)) {
      await availability?.requireCompatible();
    }
    final official =
        e.deliveryStatus == 'delivered' && e.serverSequence != null;
    if (config.mode != AppMode.serverSync ||
        (!official && !isolatedSyncHarness && availability == null)) {
      throw StateError(
        'La conciliación requiere modo servidor y compatibilidad conocida.',
      );
    }
    final p = OperacionVentaConciliadaPayload.fromJson(e.payload);
    if (!SaleAdjustmentCommandContract.sameIntention(
      e,
      SaleReconciliationCommandService.intention(p, e.userId, e.deviceId),
    )) {
      throw const FormatException('Sobre de conciliación inválido.');
    }
    if (!official) await store.validate(p, deviceId: e.deviceId);
    await store.apply(e, p, official: official);
  });
}
