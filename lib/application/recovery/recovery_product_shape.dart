/// Closed keys, including legacy fields discarded by toJson(). Value validation
/// belongs to the typed contract, which must run before this check.
class RecoveryProductShape {
  static void validate(Map<String, Object?> payload, {required bool updated}) {
    void keys(Object? value, Set<String> allowed) {
      if (value is! Map || value.keys.any((k) => !allowed.contains(k))) {
        throw const FormatException('Campo de producto no admitido.');
      }
    }

    void state(Map p) {
      keys(p, {'product', 'variants', 'dependencies'});
      final product = p['product'] as Map;
      keys(product, {'name', 'category_id', 'sale_configuration'});
      keys(product['sale_configuration'], {
        'mode',
        'sale_unit_id',
        'price_reference_quantity_atomic',
      });
      for (final raw in p['variants'] as List) {
        final v = raw as Map;
        keys(v, {
          'variant_id',
          'name',
          'sku',
          'is_default',
          'barcode',
          'sale_price_minor',
          'offer_price_minor',
          'standard_cost_minor',
          'minimum_stock_atomic',
          'inventory_item_id',
          'inventory_configuration',
          'suppliers',
          'sort_order',
        });
        if (v.containsKey('is_default') && v['is_default'] is! bool) {
          throw const FormatException('Default legado inválido.');
        }
        if (v['inventory_configuration'] != null) {
          final configuration = v['inventory_configuration'] as Map;
          keys(configuration, {'enabled', 'components'});
          for (final c in configuration['components'] as List? ?? const []) {
            keys(c, {'inventory_item_id', 'quantity_atomic'});
          }
        }
        for (final s in v['suppliers'] as List? ?? const []) {
          keys(s, {'supplier_id', 'quoted_price_minor', 'quoted_at_ms'});
        }
      }
      for (final raw in p['dependencies'] as List) {
        final d = raw as Map;
        keys(
          d,
          d['ref_type'] == 'category'
              ? {
                  'ref_type',
                  'ref_id',
                  'depends_on_event_id',
                  'base_event_id',
                  'base_version',
                  'base_server_sequence',
                }
              : d['ref_type'] == 'unit'
              ? {'ref_type', 'ref_id'}
              : {'ref_type', 'ref_id', 'depends_on_event_id'},
        );
      }
    }

    if (updated) {
      keys(payload, {'base_event_id', 'before', 'after', 'delete_product'});
      state(payload['before'] as Map);
      if (payload['after'] != null) state(payload['after'] as Map);
    } else {
      state(payload);
    }
  }
}
