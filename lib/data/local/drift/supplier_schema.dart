import 'package:sqlite3/sqlite3.dart';

/// Requisitos de tablas/columnas compartidos por arranque y restore.
/// schemaVersion permanece fijo durante desarrollo: no basta PRAGMA user_version.
bool hasCurrentSupplierSchema(Database database) {
  const requiredColumns = {
    'suppliers': {
      'id',
      'active',
      'version',
      'created_event_id',
      'last_event_id',
      'last_server_sequence',
      'name',
      'phone',
      'notes',
    },
    'variant_suppliers': {
      'variant_id',
      'supplier_id',
      'quoted_price_minor',
      'quoted_at_ms',
    },
  };
  return requiredColumns.entries.every((table) {
    final columns = database
        .select('PRAGMA table_info(${table.key})')
        .map((column) => column['name'])
        .toSet();
    return columns.containsAll(table.value);
  });
}
