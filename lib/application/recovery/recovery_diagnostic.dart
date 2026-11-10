import '../sync/payloads/cotizacion_recuperada_payload.dart';
import '../sync/payloads/cotizacion_guardada_payload.dart';
import '../sync/payloads/tarifa_venta_borrador_cambiada_payload.dart';
import '../sync/payloads/venta_borrador_limpiada_payload.dart';
import '../sync/payloads/producto_eliminado_borrador_payload.dart';
import '../sync/payloads/producto_actualizado_borrador_payload.dart';
import '../sync/payloads/producto_agregado_borrador_payload.dart';
import 'recovery_physical_provenance.dart';
import 'recovery_json.dart';
import 'recovery_reconciliation_validator.dart';
import '../sync/payloads/operacion_venta_conciliada_payload.dart';
import 'dart:convert';
import 'recovery_cancellation.dart';
import 'recovery_event_contract.dart';
import 'recovery_snapshot.dart';

/// Informe acotado: contadores completos, hasta 200 ejemplos de bloqueo.
/// Un aviso no impide generar; un bloqueo nunca se elimina por truncar ejemplos.
class RecoveryDiagnostic {
  int blockingCount = 0;
  final List<Map<String, Object?>> blockers = [];
  final List<String> warnings = [];
  final Map<String, int> counts = {};
  final Map<String, int> eventTypes = {};
  final Map<String, int> statuses = {};
  int highWatermark = 0;
  Map<String, Object?>? checkpoint;
  bool get admissible => blockingCount == 0;
  void block(String code, Object? path) {
    blockingCount++;
    if (blockers.length < 200) {
      blockers.add({
        'code': code,
        'path': path is String && path.length > 512
            ? path.substring(0, 512)
            : path,
      });
    }
  }

  Map<String, Object?> toJson() => {
    'admissible': admissible,
    'blocking_count': blockingCount,
    'blockers': blockers,
    'warnings': warnings,
    'counts': counts,
    'event_types': eventTypes,
    'delivery_statuses': statuses,
    'baseline_high_watermark': '$highWatermark',
    'checkpoint': checkpoint,
  };

  static const localEventTypes = {
    ProductoAgregadoBorradorPayload.eventType,
    ProductoActualizadoBorradorPayload.eventType,
    ProductoEliminadoBorradorPayload.eventType,
    VentaBorradorLimpiadaPayload.eventType,
    TarifaVentaBorradorCambiadaPayload.eventType,
    CotizacionGuardadaPayload.eventType,
    CotizacionRecuperadaPayload.eventType,
  };

  static Future<RecoveryDiagnostic> inspect(
    RecoverySnapshot snapshot,
    RecoveryCancellation cancellation,
  ) async {
    final d = RecoveryDiagnostic();
    final source = snapshot.cut['source'] as Map;
    if (source['mode'] != 'server_sync') {
      d.block('standalone_not_supported', 'source.mode');
    }
    if (source['identity_provenance'] == 'legacy_unknown') {
      d.warnings.add('legacy_generation_unknown');
    }
    d.warnings.add('global_server_completeness_unknown');
    for (final sequence in snapshot.duplicateOfficialSequences) {
      d.block('duplicate_official_sequence', sequence);
    }
    for (final violation in snapshot.foreignKeyViolations) {
      d.block('foreign_key', violation);
    }
    void sequence(Object? value, String path) {
      if (value == null) return;
      if (value is! int || value < 0 || value >= 9007199254740991) {
        d.block('unsafe_sequence', path);
        return;
      }
      if (value > d.highWatermark) d.highWatermark = value;
    }

    void dependency(Object? value, String path) {
      if (value == null) return;
      final e = snapshot.event(value as String);
      if (e == null) {
        d.block('missing_event', '$path -> $value');
        return;
      }
      if (e['delivery_status'] != 'delivered' ||
          e['server_sequence'] == null ||
          e['application_status'] != 'applied') {
        d.block('unaccredited_dependency', '$path -> $value');
      }
    }

    for (final table in snapshot.oversizedTables) {
      d.block('row_exceeds_4mib', table);
    }
    if (!d.admissible && snapshot.oversizedTables.isNotEmpty) return d;
    var visited = 0;
    for (final table in snapshot.tables) {
      cancellation.check();
      d.counts[table] = snapshot.count(table);
      for (final row in snapshot.rows(table)) {
        cancellation.check();
        if (++visited % 128 == 0) await Future<void>.delayed(Duration.zero);
        for (final field in row.entries) {
          if (field.key.endsWith('server_sequence')) {
            sequence(field.value, '$table.${field.key}');
          }
        }
        if (table == 'sync_checkpoints' &&
            row['checkpoint_id'] == 'full_pull') {
          d.checkpoint = {
            'last_full_pull_sequence':
                '${row['last_full_pull_server_sequence']}',
            'last_full_pull_at': null,
          };
          if (row['last_full_pull_at'] != null) {
            try {
              final timestamp = row['last_full_pull_at'];
              if (timestamp is! int) {
                throw const FormatException('Fecha no entera.');
              }
              final at = recoveryUtcFromSeconds(timestamp);
              if (!RegExp(
                r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$',
              ).hasMatch(at)) {
                throw const FormatException('Fecha no soportada.');
              }
              d.checkpoint = {
                'last_full_pull_sequence':
                    '${row['last_full_pull_server_sequence']}',
                'last_full_pull_at': at,
              };
            } catch (_) {
              d.block('incompatible_checkpoint', 'sync_checkpoints.full_pull');
            }
          }
        }
        if (table == 'events') {
          final id = row['event_id'] as String;
          final type = row['event_type'] as String;
          final status = row['delivery_status'] as String;
          final typeKey =
              RecoveryEventContract.supports(type) ||
                  localEventTypes.contains(type)
              ? type
              : 'unknown';
          d.eventTypes.update(typeKey, (v) => v + 1, ifAbsent: () => 1);
          final statusKey =
              [
                'pending',
                'delivered',
                'rejected',
                'conflict',
                'not_required',
              ].contains(status)
              ? status
              : 'unknown';
          d.statuses.update(statusKey, (v) => v + 1, ifAbsent: () => 1);
          if (row['application_status'] != 'applied') {
            d.block('application_failed', id);
          }
          if (status == 'pending') d.block('pending', id);
          if (![
            'pending',
            'delivered',
            'not_required',
            'rejected',
            'conflict',
          ].contains(status)) {
            d.block('unknown_delivery_status', id);
          }
          if (localEventTypes.contains(type)) {
            if (status != 'not_required') d.block('invalid_local_delivery', id);
            continue;
          }
          if (status == 'not_required') d.block('shared_not_required', id);
          if (status == 'delivered' &&
              (row['server_sequence'] == null ||
                  row['created_at_server'] == null)) {
            d.block('missing_official_provenance', id);
          }
          try {
            RecoveryEventContract.assertAggregate(
              type,
              row['aggregate_type'] as String,
            );
            final payload = Map<String, Object?>.from(
              jsonDecode(row['payload'] as String) as Map,
            );
            for (final dep in RecoveryEventContract.dependencies(
              type,
              payload,
            )) {
              dependency(dep, 'events.$id');
            }
          } catch (_) {
            d.block('incompatible_event_contract', id);
          }
          if (status == 'rejected' || status == 'conflict') {
            // No active=false shortcut: inspect all surviving projections below.
            if (!d.warnings.contains('historical_rejections_preserved')) {
              d.warnings.add('historical_rejections_preserved');
            }
          }
          continue;
        }
        if (table == 'sale_delivery_incidents') {
          final resolution = row['resolution_event_id'];
          if (resolution == null) {
            d.block('unresolved_incident', row['id']);
          } else {
            dependency(resolution, 'sale_delivery_incidents.${row['id']}');
            try {
              RecoveryReconciliationValidator.validateIncident(snapshot, row);
            } catch (_) {
              d.block('invalid_reconciliation_closure', row['id']);
            }
          }
          continue;
        }
        if (table == 'sale_adjustment_intents') {
          final saved = snapshot.event(row['event_id'] as String);
          if (saved == null) {
            dependency(
              row['event_id'],
              'sale_adjustment_intents.${row['operation_id']}',
            );
            continue;
          }
          try {
            final intention = Map<String, Object?>.from(
              jsonDecode(row['event_json'] as String) as Map,
            );
            final payload = Map<String, Object?>.from(
              intention['payload'] as Map,
            );
            if (payload['operation_id'] != row['operation_id'] ||
                intention['event_id'] != row['event_id'] ||
                recoveryCanonical(payload) !=
                    recoveryCanonical(jsonDecode(saved['payload'] as String)) ||
                [
                  'aggregate_type',
                  'aggregate_id',
                  'event_type',
                  'device_id',
                  'user_id',
                  'base_version',
                ].any((k) => intention[k] != saved[k]) ||
                DateTime.parse(
                          intention['created_at_local'] as String,
                        ).millisecondsSinceEpoch ~/
                        1000 !=
                    saved['created_at_local']) {
              throw StateError('Intención distinta del hecho original.');
            }
            if (['rejected', 'conflict'].contains(saved['delivery_status'])) {
              final incidents = snapshot.relatedRows(
                'sale_delivery_incidents',
                'loser_event_id',
                row['event_id'] as String,
              );
              if (incidents.length != 1 ||
                  incidents.single['resolution_event_id'] == null) {
                throw StateError('Intención física sin resolución.');
              }
              RecoveryReconciliationValidator.validateIncident(
                snapshot,
                incidents.single,
              );
            } else {
              dependency(
                row['event_id'],
                'sale_adjustment_intents.${row['operation_id']}',
              );
            }
          } catch (_) {
            d.block(
              'unresolved_or_incompatible_intention',
              row['operation_id'],
            );
          }
          continue;
        }
        if (table == 'product_update_undo') {
          d.block('optimistic_undo', row['event_id']);
          continue;
        }
        if (table == 'bulk_edit_operations') {
          if (row['local_state'] == 'confirmada') {
            d.block('unapplied_intention', row['operation_id']);
          }
          continue;
        }
        if (table == 'event_refs') {
          if (snapshot.event(row['event_id'] as String) == null) {
            d.block('orphan_event_ref', row['event_ref_id']);
          }
          continue;
        }
        if (table == 'quotations' || table == 'quotation_items') continue;
        if (table == 'sales' && row['status'] != 'confirmada') continue;
        if (table == 'sale_items') {
          final sale = snapshot.rowByKey(
            'sales',
            'id',
            row['sale_id'] as String,
          );
          if (sale == null || sale['status'] != 'confirmada') continue;
          // Confirmadas también deben acreditar sus metadatos de evento; el
          // mapper contrasta después la línea histórica y sus consumos.
        }
        if (table == 'sale_adjustments' && row['commercial_active'] == 0) {
          final incidents = snapshot.relatedRows(
            'sale_delivery_incidents',
            'loser_event_id',
            row['event_id'] as String,
          );
          if (incidents.length != 1 ||
              incidents.single['resolution_event_id'] == null) {
            d.block('unresolved_losing_branch', row['id']);
          }
          continue;
        }
        if (table == 'inventory_movements' || table == 'cash_movements') {
          final physicalId =
              row[table == 'inventory_movements' ? 'movement_id' : 'id'];
          final effect = snapshot.rowByKey(
            'sale_reconciliation_effects',
            'effect_id',
            physicalId as String,
          );
          if (effect != null) continue;
        }
        for (final field in row.entries) {
          if (field.key.endsWith('event_id') && field.value != null) {
            if (table == 'inventory_balances' && field.key == 'last_event_id') {
              try {
                final canonical = RecoveryPhysicalProvenance.balanceEvent(
                  snapshot,
                  row,
                );
                if (canonical == null) throw StateError('Saldo sin evidencia.');
                dependency(
                  canonical['event_id'],
                  'inventory_balances.last_event_id',
                );
              } catch (_) {
                d.block(
                  'unaccredited_physical_balance',
                  row['inventory_item_id'],
                );
              }
            } else {
              dependency(field.value, '$table.${field.key}');
            }
            final seqField = field.key == 'last_event_id'
                ? 'last_server_sequence'
                : field.key == 'source_event_id'
                ? 'source_server_sequence'
                : field.key == 'event_id'
                ? 'server_sequence'
                : null;
            if (seqField != null &&
                row.containsKey(seqField) &&
                row[seqField] != null &&
                snapshot.event(field.value as String)?['server_sequence'] !=
                    row[seqField]) {
              d.block('projection_sequence_mismatch', '$table.${field.key}');
            }
          }
        }
        if (row.containsKey('created_event_id') &&
            row['created_event_id'] == null) {
          d.block('missing_projection_provenance', '$table.${row['id']}');
        }
        if (table == 'sale_reconciliation_effects') {
          try {
            final e = snapshot.event(row['event_id'] as String)!;
            final p = OperacionVentaConciliadaPayload.fromJson(
              Map<String, Object?>.from(
                jsonDecode(e['payload'] as String) as Map,
              ),
            );
            final effects = [...p.preservedEffects, ...p.recoveryEffects];
            if (e['delivery_status'] != 'delivered' ||
                row['applied_locally'] != 1 ||
                effects.where((x) => x.effectId == row['effect_id']).length !=
                    1) {
              throw StateError('Efecto huérfano.');
            }
          } catch (_) {
            d.block('orphan_reconciliation_effect', row['effect_id']);
          }
        }
        // Yield periodically without retaining rows; caller can cancel between them.
        await Future<void>.value();
      }
    }
    for (final balance in snapshot.rows('inventory_balances')) {
      var sum = BigInt.zero;
      for (final movement in snapshot.relatedRows(
        'inventory_movements',
        'inventory_item_id',
        balance['inventory_item_id'] as String,
      )) {
        if (snapshot.rowByKey(
              'sale_reconciliation_effects',
              'effect_id',
              movement['movement_id'] as String,
            ) ==
            null) {
          sum += BigInt.from(movement['quantity_delta_atomic'] as int);
        }
      }
      for (final effect in snapshot.relatedRows(
        'sale_reconciliation_effects',
        'target_id',
        balance['inventory_item_id'] as String,
      )) {
        if (effect['ledger'] == 'stock') {
          sum += BigInt.from(effect['delta'] as int);
        }
      }
      if (sum != BigInt.from(balance['quantity_on_hand_atomic'] as int) ||
          sum != BigInt.from(balance['quantity_available_atomic'] as int)) {
        d.block('inventory_ledger_mismatch', balance['inventory_item_id']);
      }
    }
    for (final entity in snapshot.exportEntities) {
      try {
        for (final row in snapshot.exportRows(entity)) {
          cancellation.check();
          if (++visited % 128 == 0) await Future<void>.delayed(Duration.zero);
          recoveryCanonical(row);
        }
      } catch (error) {
        if (error is RecoveryCancelled) rethrow;
        final detail = error is StateError
            ? error.message
            : error is FormatException
            ? error.message
            : error.runtimeType.toString();
        d.block('unexportable_entity', <String, Object?>{
          'entity': entity,
          'detail': detail.length > 300 ? detail.substring(0, 300) : detail,
        });
      }
    }
    if (d.checkpoint == null) {
      d.checkpoint = {
        'last_full_pull_sequence': null,
        'last_full_pull_at': null,
      };
      d.warnings.add('no_full_pull_known');
    } else if (d.checkpoint!['last_full_pull_at'] == null) {
      d.warnings.add('full_pull_date_unknown');
    }
    return d;
  }
}
