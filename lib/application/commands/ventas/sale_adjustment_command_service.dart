import '../../sync/sale_adjustment_availability.dart';
import '../../config/app_config.dart';
import '../../config/app_config_controller.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/models/sale_adjustment_outcome.dart';
import '../../sync/payloads/sale_adjustment_payload.dart';
import '../../sync/payloads/sale_adjustment_delivery_policy.dart';
import '../../sync/payloads/venta_confirmada_payload.dart';
import '../../sync/projections/sale_adjustment_store.dart';
import '../local_command_context.dart';
import 'anular_venta_command.dart';
import 'registrar_devolucion_venta_command.dart';
import 'sale_adjustment_command_contract.dart';

/// Operaciones atómicas con compatibilidad conocida para captura offline.
class SaleAdjustmentCommandService {
  SaleAdjustmentCommandService({
    required this.store,
    required this.events,
    required this.config,
    required this.context,
    this.isolatedSyncHarness = false,
    this.availability,
  });

  /// Omite negociación únicamente en pruebas aisladas.
  final bool isolatedSyncHarness;
  final SaleAdjustmentAvailability? availability;
  final SaleAdjustmentStore store;
  final LocalEventStore events;
  final AppConfigController config;
  final LocalCommandContext context;

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

  Future<SaleAdjustmentOutcome> anular(AnularVentaCommand c) =>
      _execute(c.payload.adjustment, c.userId, c.deviceId);
  Future<SaleAdjustmentOutcome> devolver(RegistrarDevolucionVentaCommand c) =>
      _execute(c.payload.adjustment, c.userId, c.deviceId);
  Future<SyncEvent?> recoverIntention(String operationId) =>
      store.recoverIntention(operationId);

  Future<SaleAdjustmentOutcome> _execute(
    SaleAdjustmentPayload p,
    String userId,
    String deviceId,
  ) async {
    await ensureAvailable();
    final mode = config.mode == AppMode.standalone
        ? 'standalone'
        : 'server_sync';
    SaleAdjustmentDeliveryPolicy.forMode(
      mode,
      integrationVerified: isolatedSyncHarness || availability != null,
    ); // gate before journal or append
    if (userId != context.userId || deviceId != context.deviceId) {
      throw StateError('La intención pertenece a otro operador o terminal.');
    }
    final transaction = events;
    if (transaction is! LocalTransactionalEventStore) {
      throw StateError('Se requiere persistencia transaccional.');
    }
    final e = SaleAdjustmentCommandContract.intention(
      payload: p,
      mode: mode,
      userId: userId,
      deviceId: deviceId,
      integrationVerified: isolatedSyncHarness || availability != null,
    );
    await store.reserveIntention(e);
    return (transaction as LocalTransactionalEventStore).runInTransaction(
      () async {
        final previous = await store.existing(p.operationId, p.eventId);
        if (previous != null) {
          if (!SaleAdjustmentCommandContract.sameIntention(previous, e)) {
            throw StateError('La identidad ya pertenece a otra intención.');
          }
          return SaleAdjustmentOutcome(
            eventId: p.eventId,
            operationId: p.operationId,
            status: SaleAdjustmentOutcomeStatus.duplicate,
            originalStatus: switch (previous.deliveryStatus) {
              'pending' => SaleAdjustmentOutcomeStatus.pending,
              'conflict' => SaleAdjustmentOutcomeStatus.conflict,
              'rejected' => SaleAdjustmentOutcomeStatus.rejected,
              _ => SaleAdjustmentOutcomeStatus.accepted,
            },
            serverSequence: previous.serverSequence,
            reason: previous.rejectionReason,
          );
        }
        if (await store.hasIncident(p.saleId)) {
          throw StateError(
            'La venta tiene una incidencia pendiente de conciliación.',
          );
        }
        final original = await store.confirmation(p.saleId);
        if (original == null) {
          throw StateError('Se requiere una venta confirmada.');
        }
        final entry = SaleAdjustmentCommandContract.prepare(
          payload: p,
          original: VentaConfirmadaPayload.fromJson(original.payload),
          saleId: original.aggregateId,
          confirmationEventId: original.eventId,
          history: (await store.history(
            p.saleId,
          )).map((e) => SaleAdjustmentPayload.fromJson(e.payload)).toList(),
          mode: mode,
          userId: userId,
          deviceId: deviceId,
          integrationVerified: isolatedSyncHarness || availability != null,
        );
        await events.appendAndApply(entry.event, refs: entry.refs);
        return SaleAdjustmentOutcome(
          eventId: p.eventId,
          operationId: p.operationId,
          status: mode == 'server_sync'
              ? SaleAdjustmentOutcomeStatus.pending
              : SaleAdjustmentOutcomeStatus.accepted,
        );
      },
    );
  }
}
