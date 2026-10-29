import '../sale_adjustment_availability.dart';
import '../../commands/ventas/sale_adjustment_command_contract.dart';
import '../../config/app_config.dart';
import '../../config/app_config_controller.dart';
import '../models/sync_event.dart';
import '../payloads/venta_anulada_payload.dart';
import '../payloads/devolucion_venta_registrada_payload.dart';
import '../payloads/venta_confirmada_payload.dart';
import '../payloads/sale_adjustment_payload.dart';
import '../payloads/sale_adjustment_rules.dart';
import '../payloads/sale_adjustment_delivery_policy.dart';
import '../projections/sale_adjustment_store.dart';
import '../projections/cash_projection_store.dart';

class SaleAdjustmentEventHandler {
  SaleAdjustmentEventHandler({
    required this.store,
    required this.cash,
    required this.config,
    this.isolatedSyncHarness = false,
    this.availability,
  });
  final bool isolatedSyncHarness;
  final SaleAdjustmentAvailability? availability;
  final SaleAdjustmentStore store;
  final CashProjectionStore cash;
  final AppConfigController config;
  Future<void> apply(SyncEvent e) => store.atomic(() async {
    if (!(e.deliveryStatus == 'delivered' && e.serverSequence != null)) {
      await availability?.requireCompatible();
    }
    final mode = config.mode == AppMode.standalone
        ? 'standalone'
        : 'server_sync';
    final remote = e.deliveryStatus == 'delivered' && e.serverSequence != null;
    if (remote && mode == 'standalone') {
      throw StateError('Standalone no aplica entrega remota.');
    }
    SaleAdjustmentDeliveryPolicy.forMode(
      mode,
      integrationVerified:
          remote || isolatedSyncHarness || availability != null,
    );
    if (remote) await store.prepareOfficial(e);
    final p = switch (e.eventType) {
      VentaAnuladaPayload.eventType => VentaAnuladaPayload.fromJson(
        e.payload,
      ).adjustment,
      DevolucionVentaRegistradaPayload.eventType =>
        DevolucionVentaRegistradaPayload.fromJson(e.payload).adjustment,
      _ => throw const FormatException('Tipo de ajuste inválido.'),
    };
    final intention = SaleAdjustmentCommandContract.intention(
      payload: p,
      mode: mode,
      userId: e.userId,
      deviceId: e.deviceId,
      integrationVerified:
          remote || isolatedSyncHarness || availability != null,
    );
    if (!SaleAdjustmentCommandContract.sameIntention(e, intention) ||
        (mode == 'standalone' && e.baseServerSequence != null)) {
      throw const FormatException('Sobre de ajuste inválido.');
    }
    final history = await store.history(p.saleId);
    final prior = history.where(
      (h) =>
          h.eventId == p.eventId ||
          SaleAdjustmentPayload.fromJson(h.payload).operationId ==
              p.operationId,
    );
    if (prior.isNotEmpty) {
      if (prior.length != 1 ||
          !SaleAdjustmentCommandContract.sameIntention(prior.single, e)) {
        throw StateError('Identidad ocupada.');
      }
      if (e.serverSequence != null) {
        await store.acknowledge(e.eventId, e.serverSequence!);
      }
      return;
    }
    final source = await store.confirmation(p.saleId);
    if (source == null) throw StateError('Se requiere venta confirmada.');
    SaleAdjustmentCommandContract.prepare(
      payload: p,
      original: VentaConfirmadaPayload.fromJson(source.payload),
      saleId: source.aggregateId,
      confirmationEventId: source.eventId,
      history: history
          .map((h) => SaleAdjustmentPayload.fromJson(h.payload))
          .toList(),
      mode: mode,
      userId: e.userId,
      deviceId: e.deviceId,
      integrationVerified:
          remote || isolatedSyncHarness || availability != null,
    );
    final current = await cash.current(e.deviceId);
    if (!remote) {
      SaleAdjustmentRules.validateCash(
        p,
        enabled: config.config.cashEnabled,
        open: current != null,
        sessionId: current?.id,
        openingEventId: current?.createdEventId,
      );
    }
    await store.persistDocument(e, p);
    await store.applyEffects(e, p);
  });
}
