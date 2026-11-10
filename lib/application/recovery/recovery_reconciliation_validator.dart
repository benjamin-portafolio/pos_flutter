import '../sync/payloads/venta_confirmada_payload.dart';
import 'dart:convert';
import '../sync/payloads/operacion_venta_conciliada_payload.dart';
import '../sync/payloads/sale_adjustment_payload.dart';
import '../sync/payloads/sale_reconciliation_evidence.dart';
import 'recovery_json.dart';
import 'recovery_snapshot.dart';

/// Clausura de un reconocimiento oficial. Un flag applied_locally o active no
/// acredita resolución: se contrastan payload, perdedor, efectos y libros.
class RecoveryReconciliationValidator {
  static void validateIncident(
    RecoverySnapshot snapshot,
    Map<String, Object?> incident,
  ) {
    final resolution = snapshot.event(
      incident['resolution_event_id'] as String,
    );
    final loser = snapshot.event(incident['loser_event_id'] as String);
    if (resolution == null ||
        loser == null ||
        resolution['delivery_status'] != 'delivered' ||
        resolution['event_type'] != OperacionVentaConciliadaPayload.eventType ||
        loser['server_sequence'] == null ||
        loser['created_at_server'] == null ||
        !['rejected', 'conflict'].contains(loser['delivery_status'])) {
      throw StateError('Falta evidencia remota del perdedor/resolución.');
    }
    final p = OperacionVentaConciliadaPayload.fromJson(
      Map<String, Object?>.from(
        jsonDecode(resolution['payload'] as String) as Map,
      ),
    );
    final original = SaleAdjustmentPayload.fromJson(
      jsonDecode(incident['preserved_payload_json'] as String),
    );
    final fromEvent = SaleAdjustmentPayload.fromJson(
      jsonDecode(loser['payload'] as String),
    );
    if (recoveryCanonical(original.toJson()) !=
        recoveryCanonical(fromEvent.toJson())) {
      throw StateError('Evidencia del perdedor distinta.');
    }
    final base = snapshot.event(p.officialBaseEventId);
    final winner = snapshot.event(p.winnerEventId);
    if (base == null ||
        winner == null ||
        base['delivery_status'] != 'delivered' ||
        winner['delivery_status'] != 'delivered' ||
        base['aggregate_id'] != p.saleId ||
        winner['aggregate_id'] != p.saleId) {
      throw StateError('Rama oficial ausente.');
    }
    final revision = base['event_type'] == VentaConfirmadaPayload.eventType
        ? 0
        : SaleAdjustmentPayload.fromJson(
                jsonDecode(base['payload'] as String),
              ).expectedRevision +
              1;
    if (revision != p.expectedRevision) {
      throw StateError('Revisión oficial incompatible.');
    }
    p.validateIncident(
      incident: incident['id'] as String,
      sale: incident['sale_id'] as String,
      loser: incident['loser_event_id'] as String,
      winner: incident['winner_event_id'] as String,
      officialBase: p.officialBaseEventId,
      revision: revision,
      evidence: SaleReconciliationEvidence.fromAdjustment(original),
      alreadyConsumed: false,
    );
    for (final effect in [...p.preservedEffects, ...p.recoveryEffects]) {
      final r = snapshot.rowByKey(
        'sale_reconciliation_effects',
        'effect_id',
        effect.effectId,
      );
      if (r == null ||
          r['event_id'] != resolution['event_id'] ||
          r['applied_locally'] != 1 ||
          r['is_recovery'] != (p.recoveryEffects.contains(effect) ? 1 : 0) ||
          recoveryCanonical(jsonDecode(r['payload_json'] as String)) !=
              recoveryCanonical(effect.toJson()) ||
          r['ledger'] != effect.ledger ||
          r['target_id'] != effect.targetId ||
          r['delta'] != effect.delta ||
          r['cash_session_id'] != effect.cashSessionId) {
        throw StateError('Consumo de efecto incompatible.');
      }
      final stock = snapshot.rowByKey(
        'inventory_movements',
        'movement_id',
        effect.effectId,
      );
      final cash = snapshot.rowByKey('cash_movements', 'id', effect.effectId);
      if (stock != null &&
          (stock['event_id'] != p.loserEventId ||
              stock['inventory_item_id'] != effect.targetId ||
              stock['quantity_delta_atomic'] != effect.delta)) {
        throw StateError('Libro físico de stock incompatible.');
      }
      if (cash != null &&
          (cash['created_event_id'] != p.loserEventId ||
              cash['session_id'] != effect.cashSessionId ||
              (cash['direction'] == 'in'
                      ? cash['amount_minor']
                      : -(cash['amount_minor'] as int)) !=
                  effect.delta)) {
        throw StateError('Libro físico de caja incompatible.');
      }
    }
  }
}
