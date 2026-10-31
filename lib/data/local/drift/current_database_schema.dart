import 'package:sqlite3/sqlite3.dart';

import 'offer_pricing_schema.dart';

/// Huella física compartida por arranque y restore.
/// Restore usa la misma comprobación antes de reemplazar la base vigente.
/// La versión numérica por sí sola no acredita compatibilidad en desarrollo.
bool hasCurrentAppDatabaseSchema(Database connection) =>
    hasRecognizedOfferSchema(connection);

/// Comprobación específica usada también en pruebas de ajustes.
bool hasSaleAdjustmentSchema(Database connection) =>
    connection
            .select(
              "SELECT 1 FROM sqlite_master WHERE type='table' AND name IN ('sale_adjustments','sale_adjustment_lines','sale_credit_reductions','sale_adjustment_intents','sale_delivery_incidents','sale_reconciliation_effects')",
            )
            .length ==
        6 &&
    connection
            .select(
              "SELECT 1 FROM sqlite_master WHERE type='index' AND name IN ('ux_sale_void','ux_sale_adjustment_revision')",
            )
            .length ==
        2 &&
    {
      'sale_adjustments': {
        'commercial_active',
        'id',
        'sale_id',
        'confirmation_event_id',
        'base_event_id',
        'event_id',
        'kind',
        'revision',
        'business_date',
        'occurred_at_ms',
        'utc_offset_minutes',
        'reason',
        'user_id',
        'device_id',
        'amount_minor',
        'method',
        'sale_payment_id',
        'cliente_id',
        'currency',
        'settlement_reference',
        'cash_enabled',
        'settlement_action',
        'payload_json',
      },
      'sale_adjustment_lines': {
        'operation_id',
        'sale_item_id',
        'quantity_atomic',
        'amount_minor',
        'recovered_cost_minor',
        'destination',
        'reason',
      },
      'sale_credit_reductions': {'operation_id', 'credit_id', 'amount_minor'},
      'sale_adjustment_intents': {'operation_id', 'event_id', 'event_json'},
      'sale_reconciliation_effects': {
        'effect_id',
        'event_id',
        'ledger',
        'target_id',
        'delta',
        'cash_session_id',
        'payload_json',
        'applied_locally',
        'is_recovery',
      },
      'sale_delivery_incidents': {
        'id',
        'sale_id',
        'loser_event_id',
        'winner_event_id',
        'blocked_by_event_id',
        'reason',
        'preserved_payload_json',
        'resolution_event_id',
      },
    }.entries.every(
      (entry) => connection
          .select('PRAGMA table_info(${entry.key})')
          .map((c) => c['name'])
          .toSet()
          .containsAll(entry.value),
    ) &&
    ['cash_movements', 'inventory_movements'].every(
      (table) => connection
          .select('PRAGMA table_info($table)')
          .any((c) => c['name'] == 'sale_adjustment_id'),
    );
