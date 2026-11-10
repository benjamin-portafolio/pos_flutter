import '../../../application/recovery/recovery_json.dart';
import '../../../application/recovery/recovery_physical_provenance.dart';
import 'dart:convert';
import '../../../application/recovery/recovery_snapshot.dart';
import '../../../application/sync/payloads/venta_confirmada_payload.dart';
import 'recovery_columns.dart';

/// Adaptación explícita v10→contrato lógico S1. No ejecuta handlers, no rellena
/// negocio ausente. Fechas SQLite Drift son segundos UTC, no milisegundos.
class RecoveryRowMapper {
  RecoveryRowMapper(this.snapshot);
  final RecoverySnapshot snapshot;
  Map<String, Object?>? map(String table, Map<String, Object?> local) {
    final values = Map<String, Object?>.from(local);
    if (table == 'espacios' &&
        values['identificacion'] is String &&
        (values['identificacion'] as String).trim().isEmpty) {
      throw StateError(
        'Identificación vacía incompatible con unicidad PostgreSQL.',
      );
    }
    if (table == 'inventory_balances') {
      final canonical = RecoveryPhysicalProvenance.balanceEvent(
        snapshot,
        values,
      );
      if (canonical == null) throw StateError('Saldo sin procedencia oficial.');
      if (canonical['event_id'] != values['last_event_id']) {
        values['last_event_id'] = canonical['event_id'];
        values['last_server_sequence'] = canonical['server_sequence'];
      }
    }
    if (table == 'events') {
      if (![
            'delivered',
            'rejected',
            'conflict',
          ].contains(values['delivery_status']) ||
          values['server_sequence'] == null ||
          values['created_at_server'] == null) {
        return null;
      }
      values['sync_status'] = values['delivery_status'] == 'delivered'
          ? 'synced'
          : values['delivery_status'];
      values['updated_at_server'] = null;
      values['local_sequence'] = null;
    }
    if (table == 'sales') {
      if (values['status'] != 'confirmada') return null;
      final e = snapshot.event(values['created_event_id'] as String);
      if (e == null || e['event_type'] != VentaConfirmadaPayload.eventType) {
        throw StateError('Confirmación ausente: ${values['id']}');
      }
      values['currency'] = VentaConfirmadaPayload.fromJson(
        Map<String, Object?>.from(jsonDecode(e['payload'] as String) as Map),
      ).currency;
    }
    if (table == 'sale_items') {
      // Consulta puntual por venta mediante índice de PK de la captura.
      final sale = snapshot.rowByKey(
        'sales',
        'id',
        values['sale_id'] as String,
      );
      if (sale == null) throw StateError('Venta ausente.');
      if (sale['status'] != 'confirmada') return null;
      final e = snapshot.event(sale['created_event_id'] as String);
      if (e == null || e['event_type'] != VentaConfirmadaPayload.eventType) {
        throw StateError('Confirmación ausente.');
      }
      final payload = VentaConfirmadaPayload.fromJson(
        Map<String, Object?>.from(jsonDecode(e['payload'] as String) as Map),
      );
      final lines = payload.lines.where((l) => l.id == values['id']).toList();
      if (lines.length != 1) {
        throw StateError('Línea original ausente: ${values['id']}');
      }
      final line = lines.single;
      final historical = line.snapshot.toJson();
      for (final field in historical.entries) {
        if (values.containsKey(field.key) && values[field.key] != field.value) {
          throw StateError(
            'Snapshot histórico distinto: ${values['id']}.${field.key}',
          );
        }
      }
      if (line.snapshot.variantId != values['variant_id'] ||
          payload.lines.indexOf(line) != values['sort_order'] ||
          line.snapshot.totalMinor != values['total_minor']) {
        throw StateError('Línea histórica distinta.');
      }
      for (final c in line.consumptions) {
        if (c.movementId == null) continue;
        final movement = snapshot.rowByKey(
          'inventory_movements',
          'movement_id',
          c.movementId!,
        );
        if (movement == null ||
            movement['event_id'] != e['event_id'] ||
            movement['sale_item_id'] != line.id ||
            movement['inventory_item_id'] != c.inventoryItemId ||
            movement['quantity_delta_atomic'] != c.deltaAtomic) {
          throw StateError('Consumo histórico ausente o distinto.');
        }
      }
      values['snapshot'] = line.toJson();
    }
    if (table == 'inventory_movements' || table == 'cash_movements') {
      if (snapshot.rowByKey(
            'sale_reconciliation_effects',
            'effect_id',
            values[table == 'inventory_movements' ? 'movement_id' : 'id']
                as String,
          ) !=
          null) {
        return null;
      }
    }
    if (table == 'sale_adjustment_lines' || table == 'sale_credit_reductions') {
      final parent = snapshot.rowByKey(
        'sale_adjustments',
        'id',
        values['operation_id'] as String,
      );
      if (parent == null) throw StateError('Ajuste ausente.');
      if (parent['commercial_active'] == 0) return null;
    }
    if (table == 'sale_adjustments') {
      if (values['commercial_active'] != 1) return null;
      values['total_minor'] = values['amount_minor'];
      values['payment_id'] = values['sale_payment_id'];
      values['reference'] = values['settlement_reference'];
    }
    if (table == 'sale_reconciliation_effects') {
      values['payload'] = values['payload_json'];
    }
    final idColumn = recoveryIdentityColumns[table];
    if (idColumn != null) values[idColumn] = values['id'];
    final columns = recoveryColumns[table];
    if (columns == null) {
      throw UnsupportedError('Entidad no exportable: $table');
    }
    return {
      for (final field in columns.entries)
        field.key: _convert(
          field.key,
          field.value,
          _required(values, field.key),
        ),
    };
  }

  Object? _required(Map<String, Object?> values, String key) {
    if (!values.containsKey(key)) {
      throw StateError('Campo requerido ausente: $key');
    }
    return values[key];
  }

  Object? _convert(String field, String type, Object? value) {
    if (value == null) return null;
    switch (type) {
      case 'boolean':
        if (value != 0 && value != 1) {
          throw FormatException('Booleano inválido: $field');
        }
        return value == 1;
      case 'numeric':
        final exact = BigInt.tryParse('$value');
        if (exact == null) {
          throw FormatException('Total exacto inválido: $field');
        }
        return exact.toString();
      case 'bigint':
        final parsed = BigInt.tryParse('$value');
        if (parsed == null || parsed.abs() > BigInt.from(9007199254740991)) {
          throw FormatException('Entero fuera de rango: $field');
        }
        return parsed.toString();
      case 'integer':
        if (value is! int ||
            value < -9007199254740991 ||
            value > 9007199254740991) {
          throw FormatException('Entero inválido: $field');
        }
        return value;
      case 'timestamptz':
        return recoveryUtcFromSeconds(value);
      case 'jsonb':
        return value is String ? jsonDecode(value) : value;
      case 'uuid':
        if (value is! String ||
            !RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ).hasMatch(value)) {
          throw FormatException('UUID inválido: $field');
        }
        return value;
      default:
        return value;
    }
  }
}
