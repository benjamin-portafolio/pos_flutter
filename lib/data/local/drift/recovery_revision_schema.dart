/// Inventario cerrado v9. Incluye diarios y checkpoints: su cambio impide
/// sustituir el origen al vincular, aunque no avance local_sequence.
const recoveryRevisionTables = <String>[
  'account_balance_baselines',
  'bulk_edit_operations',
  'cash_movements',
  'cash_sessions',
  'categories',
  'clientes',
  'credit_allocations',
  'credit_sales',
  'customer_payments',
  'espacios',
  'event_refs',
  'events',
  'financial_categories',
  'financial_entries',
  'inventory_balances',
  'inventory_item_discards',
  'inventory_items',
  'inventory_movements',
  'product_update_undo',
  'product_variants',
  'products',
  'quotation_items',
  'quotations',
  'recipe_components',
  'sale_adjustment_intents',
  'sale_adjustment_lines',
  'sale_adjustments',
  'sale_credit_reductions',
  'sale_delivery_incidents',
  'sale_items',
  'sale_payments',
  'sale_reconciliation_effects',
  'sales',
  'suppliers',
  'sync_checkpoints',
  'units',
  'variant_inventory_memory',
  'variant_suppliers',
];

const recoveryStateDdl =
    'CREATE TABLE "recovery_local_state" ('
    '"singleton" INTEGER NOT NULL CHECK (singleton = 1), '
    '"data_revision" INTEGER NOT NULL DEFAULT 0, '
    '"server_instance_id" TEXT NULL, "generation_id" TEXT NULL, "dataset_id" TEXT NULL, PRIMARY KEY ("singleton"))';

final recoveryRevisionTriggers = <String>[
  for (final table in recoveryRevisionTables)
    for (final op in ['INSERT', 'UPDATE', 'DELETE'])
      'CREATE TRIGGER recovery_revision_${table}_${op.toLowerCase()} AFTER $op ON $table '
          'BEGIN UPDATE recovery_local_state SET data_revision = data_revision + 1 '
          'WHERE singleton = 1; END',
];
