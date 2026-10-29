import '../../sync/sale_adjustment_availability.dart';
import '../../config/app_config.dart';
import '../../config/app_config_controller.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/operacion_venta_conciliada_payload.dart';
import '../../sync/projections/sale_reconciliation_store.dart';
import '../local_command_context.dart';
import 'conciliar_operacion_venta_command.dart';
import 'sale_adjustment_command_contract.dart';

class SaleReconciliationCommandService {
  SaleReconciliationCommandService({
    required this.store,
    required this.events,
    required this.config,
    required this.context,
    this.isolatedSyncHarness = false,
    this.availability,
  });
  final SaleReconciliationStore store;
  final LocalEventStore events;
  final AppConfigController config;
  final LocalCommandContext context;
  final bool isolatedSyncHarness;
  final SaleAdjustmentAvailability? availability;
  Future<void> ensureAvailable({bool refresh = false}) async {
    if (config.mode == AppMode.standalone) return;
    if (availability != null) {
      await availability!.requireCompatible(refresh: refresh);
    } else if (!isolatedSyncHarness) {
      throw StateError(
        'No se configuró la verificación de compatibilidad del servidor.',
      );
    }
  }

  static SyncEvent intention(
    OperacionVentaConciliadaPayload p,
    String user,
    String device,
  ) => SyncEvent(
    eventId: p.eventId,
    aggregateType: OperacionVentaConciliadaPayload.aggregateType,
    aggregateId: p.saleId,
    eventType: OperacionVentaConciliadaPayload.eventType,
    deviceId: device,
    userId: user,
    createdAtLocal: DateTime.fromMillisecondsSinceEpoch(
      p.occurredAtMs,
      isUtc: true,
    ),
    baseVersion: p.expectedRevision + 1,
    payload: p.toJson(),
  );
  Future<String> conciliar(ConciliarOperacionVentaCommand c) async {
    final refs = c.payload.refs;
    if (refs.isEmpty ||
        refs.any(
          (r) =>
              r.refId.trim().isEmpty ||
              !['affects', 'uses'].contains(r.relationship),
        )) {
      throw StateError('Referencias inválidas.');
    }
    if (config.mode != AppMode.serverSync) {
      throw StateError('La conciliación requiere modo servidor.');
    }
    await ensureAvailable();
    if (c.userId != context.userId || c.deviceId != context.deviceId) {
      throw StateError('Operador o terminal distintos.');
    }
    final e = intention(c.payload, c.userId, c.deviceId);
    await store.reserveIntention(e);
    return store.atomic(() async {
      final previous = await store.existing(
        c.payload.operationId,
        c.payload.eventId,
      );
      if (previous != null) {
        if (!SaleAdjustmentCommandContract.sameIntention(previous, e)) {
          throw StateError('Identidad ocupada por otra intención.');
        }
        return previous.eventId;
      }
      await store.validate(c.payload, deviceId: context.deviceId);
      await events.appendAndApply(e, refs: refs);
      return e.eventId;
    });
  }
}
