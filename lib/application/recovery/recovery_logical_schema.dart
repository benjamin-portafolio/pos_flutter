/// PK del contrato lógico, incluidas las evidencias que no son negocio SQL.
/// La comparación ordenada permite detectar duplicados entre lotes con memoria O(1).
class RecoveryLogicalSchema {
  static const keys = <String, List<String>>{
    'account_balance_baselines': ['id'],
    'cash_movements': ['id'],
    'cash_sessions': ['id'],
    'categories': ['category_id'],
    'clientes': ['cliente_id'],
    'credit_allocations': ['payment_id', 'credit_id'],
    'credit_sales': ['id'],
    'customer_payments': ['id'],
    'espacios': ['espacio_id'],
    'event_refs': ['event_ref_id'],
    'events': ['event_id'],
    'event_provenance': ['event_id'],
    'projection_provenance': ['entity', 'row_id'],
    'financial_categories': ['id'],
    'financial_entries': ['id'],
    'inventory_balances': ['inventory_item_id'],
    'inventory_item_discards': ['inventory_item_id'],
    'inventory_items': ['inventory_item_id'],
    'inventory_movements': ['movement_id'],
    'product_variants': ['variant_id'],
    'products': ['product_id'],
    'recipe_components': ['variant_id', 'inventory_item_id'],
    'sale_adjustment_lines': ['operation_id', 'sale_item_id'],
    'sale_adjustments': ['id'],
    'sale_adjustment_evidence': ['id'],
    'sale_credit_reductions': ['operation_id', 'credit_id'],
    'sale_delivery_incidents': ['id'],
    'sale_items': ['sale_item_id'],
    'sale_payments': ['payment_id'],
    'sale_reconciliation_effects': ['effect_id'],
    'sales': ['sale_id'],
    'suppliers': ['supplier_id'],
    'units': ['unit_id'],
    'variant_inventory_memory': ['variant_id'],
    'variant_suppliers': ['variant_id', 'supplier_id'],
    'sale_presentation_metadata': ['sale_id'],
  };
  static List<String> key(String entity, Map<String, Object?> row) {
    final columns = keys[entity];
    if (columns == null) throw FormatException('Entidad desconocida: $entity');
    return [
      for (final c in columns)
        if (row[c] is String)
          row[c] as String
        else
          throw FormatException('PK inválida: $entity.$c'),
    ];
  }

  static int compare(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}
