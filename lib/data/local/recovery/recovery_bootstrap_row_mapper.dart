import 'dart:convert';
import '../../../application/sync/payloads/confirmed_sale_line.dart';
import '../../../application/sync/payloads/sale_adjustment_payload.dart';
import 'recovery_columns.dart';

typedef BootstrapLocalRow = ({String table, Map<String, Object?> values});

/// Inversa cerrada del paquete v1. Nunca ejecuta comandos ni handlers históricos.
class RecoveryBootstrapRowMapper {
  RecoveryBootstrapRowMapper({required this.convert, required this.lookup});
  final Object? Function(String field, String type, Object? value) convert;
  final Future<Map<String, Object?>?> Function(String entity, List<String> key)
  lookup;

  Future<List<BootstrapLocalRow>> map(
    String entity,
    Map<String, Object?> row,
  ) async {
    if (entity == 'event_provenance' || entity == 'projection_provenance') {
      return [];
    }
    if (entity == 'inventory_item_discards') {
      throw const FormatException(
        'El descarte standalone no es importable en server_sync.',
      );
    }
    if (entity == 'sale_presentation_metadata') return [];
    if (entity == 'sale_adjustment_evidence' ||
        entity == 'sale_delivery_incidents') {
      final values = <String, Object?>{};
      for (final field in row.entries) {
        final value = field.value;
        values[field.key] = field.key.endsWith('_json')
            ? jsonEncode(value)
            : value is bool
            ? (value ? 1 : 0)
            : value is String && _integerFields.contains(field.key)
            ? convert(field.key, 'bigint', value)
            : value;
      }
      if (entity == 'sale_delivery_incidents') {
        return [(table: entity, values: values)];
      }
      final p = SaleAdjustmentPayload.fromJson(row['payload_json']);
      return [
        (table: 'sale_adjustments', values: values),
        ..._evidenceLines(p),
      ];
    }
    final columns = recoveryColumns[entity];
    if (columns == null ||
        columns.length != row.length ||
        columns.keys.any((key) => !row.containsKey(key))) {
      throw FormatException('Columnas bootstrap incompatibles: $entity');
    }
    final local = <String, Object?>{};
    for (final field in columns.entries) {
      if (entity == 'events' &&
          {
            'local_sequence',
            'sync_status',
            'updated_at_server',
          }.contains(field.key)) {
        continue;
      }
      local[recoveryIdentityColumns[entity] == field.key ? 'id' : field.key] =
          convert(field.key, field.value, row[field.key]);
    }
    if (entity == 'events') {
      local['application_status'] = 'applied';
      local['delivery_status'] = row['sync_status'] == 'synced'
          ? 'delivered'
          : row['sync_status'];
    } else if (entity == 'sales') {
      local.remove('currency');
      final provenance = await lookup('sale_presentation_metadata', [
        row['sale_id'] as String,
      ]);
      if (provenance == null) {
        throw const FormatException('Falta procedencia temporal de venta.');
      }
      local['updated_at_local'] = convert(
        'updated_at_local',
        'timestamptz',
        provenance['updated_at_local'],
      );
    } else if (entity == 'sale_items') {
      local.remove('snapshot');
      final line = ConfirmedSaleLine.fromJson(
        Map<String, Object?>.from(row['snapshot'] as Map),
      );
      local.addAll(line.snapshot.toJson());
    } else if (entity == 'sale_adjustments') {
      local['amount_minor'] = local.remove('total_minor');
      local['sale_payment_id'] = local.remove('payment_id');
      local['settlement_reference'] = local.remove('reference');
      final evidence = await lookup('events', [row['event_id'] as String]);
      if (evidence == null) {
        throw const FormatException('Falta evento del ajuste.');
      }
      final p = SaleAdjustmentPayload.fromJson(evidence['payload']);
      local.addAll({
        'commercial_active': 1,
        'confirmation_event_id': p.confirmationEventId,
        'base_event_id': p.previousAdjustmentEventId ?? p.confirmationEventId,
        'user_id': evidence['user_id'],
        'device_id': evidence['device_id'],
        'cash_enabled': p.settlement.cashEnabled ? 1 : 0,
        'payload_json': jsonEncode(p.toJson()),
      });
    } else if (entity == 'sale_reconciliation_effects') {
      local['payload_json'] = local.remove('payload');
      local['applied_locally'] = 1;
    }
    return [(table: entity, values: local)];
  }

  List<BootstrapLocalRow> _evidenceLines(SaleAdjustmentPayload p) => [
    for (final l in p.lines)
      (
        table: 'sale_adjustment_lines',
        values: {
          'operation_id': p.operationId,
          'sale_item_id': l.saleItemId,
          'quantity_atomic': l.quantityAtomic,
          'amount_minor': l.amountMinor,
          'recovered_cost_minor': l.recoveredCostMinor,
          'destination': l.destination,
          'reason': l.reason,
        },
      ),
    if (p.settlement.method == 'credit' && p.totalMinor > 0)
      (
        table: 'sale_credit_reductions',
        values: {
          'operation_id': p.operationId,
          'credit_id': p.saleId,
          'amount_minor': p.totalMinor,
        },
      ),
  ];
  static const _integerFields = {
    'last_server_sequence',
    'amount_minor',
    'occurred_at_ms',
  };
}
