import 'package:sqlite3/sqlite3.dart';

import 'supplier_schema.dart';

/// Esquema que el arranque acepta sin reiniciar una base existente.
/// Restore usa la misma comprobación antes de reemplazar la base vigente.
/// La versión numérica por sí sola no acredita compatibilidad en desarrollo.
bool hasCurrentAppDatabaseSchema(Database connection) {
  final variantColumns = connection.select(
    'PRAGMA table_info(product_variants)',
  );
  final paymentColumns = connection.select('PRAGMA table_info(sale_payments)');
  final inventoryItemColumns = connection.select(
    'PRAGMA table_info(inventory_items)',
  );
  final quotationColumns = connection
      .select('PRAGMA table_info(quotations)')
      .map((column) => column['name'])
      .toSet();
  final quotationItemColumns = connection
      .select('PRAGMA table_info(quotation_items)')
      .map((column) => column['name'])
      .toSet();
  final bulkColumns = connection
      .select('PRAGMA table_info(bulk_edit_operations)')
      .map((column) => column['name'])
      .toSet();
  return connection.select('PRAGMA user_version').single['user_version'] == 8 &&
      hasSaleAdjustmentSchema(connection) &&
      connection
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'ix_sales_local_drafts'",
          )
          .isNotEmpty &&
      connection
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'ux_sales_local_draft'",
          )
          .isEmpty &&
      bulkColumns.containsAll({
        'operation_id',
        'batch_id',
        'product_id',
        'mode',
        'intent_json',
        'local_state',
        'result_json',
        'confirmed_at',
        'finished_at',
      }) &&
      connection
              .select(
                "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'ux_bulk_edit_batch_product'",
              )
              .length ==
          1 &&
      hasCurrentSupplierSchema(connection) &&
      !quotationColumns.any({'currency', 'total_minor'}.contains) &&
      !quotationItemColumns.any(
        {
          'unit_price_minor',
          'standard_cost_minor_snapshot',
          'total_minor',
          'price_reference_quantity_atomic_snapshot',
          'consumption_configuration_key',
        }.contains,
      ) &&
      quotationColumns.containsAll({
        'id',
        'active',
        'version',
        'created_event_id',
        'last_event_id',
        'last_server_sequence',
        'user_id',
        'device_id',
        'issued_at_local',
        'source_sale_id',
        'source_draft_event_id',
        'current_sale_id',
      }) &&
      quotationItemColumns.containsAll({
        'id',
        'active',
        'version',
        'created_event_id',
        'last_event_id',
        'last_server_sequence',
        'quotation_id',
        'variant_id',
        'product_name_snapshot',
        'variant_name_snapshot',
        'sale_mode_snapshot',
        'quantity',
        'measured_quantity_atomic',
        'sale_unit_code_snapshot',
        'sale_unit_symbol_snapshot',
        'sale_unit_atomic_factor_snapshot',
        'sort_order',
      }) &&
      connection
              .select(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name IN ('quotations', 'quotation_items')",
              )
              .length ==
          2 &&
      connection
              .select(
                "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name IN ('ix_quotations_listing', 'ux_quotations_current_sale', 'ux_quotation_items_order')",
              )
              .length ==
          3 &&
      connection
              .select(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name IN ('cash_sessions', 'cash_movements')",
              )
              .length ==
          2 &&
      paymentColumns.any((column) => column['name'] == 'method') &&
      paymentColumns.any((column) => column['name'] == 'reference') &&
      connection
              .select(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name IN ('credit_allocations', 'credit_sales', 'customer_payments')",
              )
              .length ==
          3 &&
      connection
              .select(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name IN ('financial_categories', 'financial_entries')",
              )
              .length ==
          2 &&
      connection
          .select('PRAGMA table_info(sales)')
          .any((column) => column['name'] == 'cliente_id') &&
      connection
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'clientes'",
          )
          .isNotEmpty &&
      connection
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'product_update_undo'",
          )
          .isNotEmpty &&
      connection
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sale_payments'",
          )
          .isNotEmpty &&
      connection
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sale_items'",
          )
          .isNotEmpty &&
      variantColumns.isNotEmpty &&
      variantColumns.any((column) => column['name'] == 'barcode') &&
      variantColumns.any(
        (column) => column['name'] == 'minimum_stock_atomic',
      ) &&
      !variantColumns.any((column) => column['name'] == 'is_default') &&
      connection
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'variant_inventory_memory'",
          )
          .isNotEmpty &&
      connection
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'inventory_item_discards'",
          )
          .isNotEmpty &&
      inventoryItemColumns.isNotEmpty &&
      inventoryItemColumns.any(
        (column) => column['name'] == 'origin_variant_id',
      );
}

/// Desarrollo: rechazar esquemas previos sin migrar ni cambiar schemaVersion.
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
