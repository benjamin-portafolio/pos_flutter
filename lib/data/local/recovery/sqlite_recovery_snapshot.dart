import '../../../application/recovery/recovery_physical_provenance.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart' as ids;
import '../../../application/recovery/recovery_diagnostic.dart';
import '../../../application/recovery/recovery_json.dart';
import '../../../application/recovery/recovery_snapshot.dart';
import '../drift/current_database_schema.dart';
import '../drift/recovery_revision_schema.dart';
import 'recovery_columns.dart';
import 'recovery_row_mapper.dart';

/// SQLite es abierto readOnly; cada iterador retiene como máximo una fila.
/// La lista permitida se comprueba antes de interpolar nombres de tabla.
class SqliteRecoverySnapshot implements RecoverySnapshot {
  /// Reabre solo una captura local completa y verifica su digest antes de leer.
  static Future<SqliteRecoverySnapshot> open(File file) async {
    final text = await File('${file.parent.path}/cut.json').readAsString();
    final cut = Map<String, Object?>.from(jsonDecode(text) as Map);
    if (text != recoveryCanonical(cut) ||
        (await sha256.bind(file.openRead()).first).toString() !=
            cut['snapshot_sha256']) {
      throw StateError('Captura alterada.');
    }
    final raw = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      if (!hasCurrentAppDatabaseSchema(raw) ||
          raw.select('PRAGMA integrity_check').single.values.single != 'ok' ||
          raw
                  .select(
                    'SELECT data_revision FROM recovery_local_state WHERE singleton=1',
                  )
                  .single['data_revision']
                  .toString() !=
              cut['data_revision']) {
        throw StateError('Corte incompatible.');
      }
      return SqliteRecoverySnapshot(file, cut, raw);
    } catch (_) {
      raw.close();
      rethrow;
    }
  }

  SqliteRecoverySnapshot(this.file, Map<String, Object?> cut, this._db)
    : cut = Map.unmodifiable({
        ...cut,
        'source': Map<String, Object?>.unmodifiable(
          cut['source'] as Map<String, Object?>,
        ),
      }) {
    _db.execute('PRAGMA temp_store=FILE');
    _db.execute('PRAGMA cache_size=-2048');
    _db.createFunction(
      functionName: 'recovery_ref_id',
      function: (args) => _refId(args),
      deterministic: true,
    );
  }
  static String _refId(List<Object?> values) => const ids.Uuid().v5(
    'edca57ad-e713-5b34-9658-a340690a788f',
    recoveryCanonical(values),
  );
  final Database _db;
  @override
  final File file;
  @override
  final Map<String, Object?> cut;
  @override
  List<String> get tables => recoveryRevisionTables;
  @override
  List<String> get duplicateOfficialSequences => _db
      .select(
        'SELECT server_sequence FROM events WHERE server_sequence IS NOT NULL GROUP BY server_sequence HAVING count(*)>1 LIMIT 200',
      )
      .map((r) => r['server_sequence'].toString())
      .toList();
  @override
  List<String> get oversizedTables => [
    for (final table in tables)
      if (_oversized(table)) table,
  ];
  bool _oversized(String table) {
    final cols = _db.select('PRAGMA table_info("$table")');
    final size = cols
        .map((c) => 'coalesce(length(CAST("${c['name']}" AS BLOB)),0)')
        .join('+');
    return _db
        .select('SELECT 1 FROM "$table" WHERE ($size)>4194304 LIMIT 1')
        .isNotEmpty;
  }

  void _check(String table) {
    if (!tables.contains(table)) throw ArgumentError.value(table);
  }

  @override
  List<String> get exportEntities => [
    ...recoveryColumns.keys,
    'event_provenance',
    'projection_provenance',
    'sale_adjustment_evidence',
    'inventory_item_discards',
    'sale_delivery_incidents',
    'sale_presentation_metadata',
  ]..sort();
  @override
  Iterable<Map<String, Object?>> exportRows(String entity) sync* {
    if (entity == 'projection_provenance') {
      for (final r in rows('inventory_balances')) {
        final canonical = RecoveryPhysicalProvenance.balanceEvent(this, r);
        if (canonical != null && canonical['event_id'] != r['last_event_id']) {
          yield {
            'entity': 'inventory_balances',
            'row_id': r['inventory_item_id'],
            'source_row': _sidecar(r),
            'canonical_event_id': canonical['event_id'],
            'rule': 'delivered_reconciliation_once',
          };
        }
      }
      return;
    }
    if (entity == 'sale_adjustment_evidence') {
      for (final r in rows('sale_adjustments')) {
        if (r['commercial_active'] == 0) yield _sidecar(r);
      }
      return;
    }
    if (entity == 'event_provenance') {
      for (final r in rows('events')) {
        if (RecoveryDiagnostic.localEventTypes.contains(r['event_type'])) {
          continue;
        }
        yield {
          'event_id': r['event_id'],
          'observed_local_sequence': '${r['local_sequence']}',
          'sequence_origin': 'sqlite_insertion_order',
          'application_status': r['application_status'],
          'delivery_status': r['delivery_status'],
          'non_official_evidence':
              r['server_sequence'] == null || r['created_at_server'] == null
              ? {...r, 'payload': jsonDecode(r['payload'] as String)}
              : null,
        };
      }
      return;
    }
    if (entity == 'inventory_item_discards' ||
        entity == 'sale_delivery_incidents') {
      for (final r in rows(entity)) {
        yield _sidecar(r);
      }
      return;
    }
    if (entity == 'sale_presentation_metadata') {
      for (final r in rows('sales')) {
        if (r['status'] != 'confirmada') continue;
        yield {
          'sale_id': r['id'],
          'created_at_local': recoveryUtcFromSeconds(r['created_at_local']),
          'updated_at_local': recoveryUtcFromSeconds(r['updated_at_local']),
          'timestamp_origin': 'source_sqlite',
        };
      }
      return;
    }
    if (!recoveryColumns.containsKey(entity)) throw ArgumentError.value(entity);
    final mapper = RecoveryRowMapper(this);
    String? previousRefId;
    for (final row in rows(entity)) {
      if (entity == 'events' &&
          RecoveryDiagnostic.localEventTypes.contains(row['event_type'])) {
        continue;
      }
      if (entity == 'event_refs') {
        final e = event(row['event_id'] as String);
        if (e == null ||
            e['delivery_status'] != 'delivered' ||
            RecoveryDiagnostic.localEventTypes.contains(e['event_type'])) {
          continue;
        }
        row['source'] = 'server';
        row['server_sequence'] = e['server_sequence'];
        row['event_ref_id'] = _refId([
          row['event_id'],
          row['ref_type'],
          row['ref_id'],
          row['relationship'],
        ]);
        if (row['event_ref_id'] == previousRefId) continue;
        previousRefId = row['event_ref_id'] as String;
      }
      final mapped = mapper.map(entity, row);
      if (mapped != null) yield mapped;
    }
  }

  @override
  int count(String table) {
    _check(table);
    return _db.select('SELECT count(*) AS n FROM "$table"').single['n'] as int;
  }

  @override
  Iterable<Map<String, Object?>> rows(String table) sync* {
    _check(table);
    final columns = _db.select('PRAGMA table_info("$table")');
    final pk = columns.where((c) => (c['pk'] as int) > 0).toList()
      ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    final order = table == 'events'
        ? 'event_id'
        : table == 'event_refs'
        ? 'recovery_ref_id(event_id,ref_type,ref_id,relationship)'
        : pk.isEmpty
        ? 'rowid'
        : pk.map((c) => '"${c['name']}"').join(',');
    // Rechazo previo en SQLite: no traer a Dart un BLOB/texto sin límite.
    final size = columns
        .map((c) => 'coalesce(length(CAST("${c['name']}" AS BLOB)),0)')
        .join('+');
    if (_db
        .select('SELECT 1 FROM "$table" WHERE ($size) > 4194304 LIMIT 1')
        .isNotEmpty) {
      throw StateError('Fila mayor de 4 MiB en $table.');
    }
    final statement = _db.prepare('SELECT * FROM "$table" ORDER BY $order');
    try {
      final cursor = statement.selectCursor();
      while (cursor.moveNext()) {
        yield Map<String, Object?>.from(cursor.current);
      }
    } finally {
      statement.close();
    }
  }

  Map<String, Object?> _sidecar(Map<String, Object?> r) => {
    for (final e in r.entries)
      e.key: e.key.endsWith('_json')
          ? jsonDecode(e.value as String)
          : [
              'active',
              'commercial_active',
              'applied_locally',
              'cash_enabled',
              'is_recovery',
            ].contains(e.key)
          ? e.value == 1
          : e.value is int &&
                !['version', 'revision', 'utc_offset_minutes'].contains(e.key)
          ? '${e.value}'
          : e.value,
  };
  @override
  Iterable<Map<String, Object?>> relatedRows(
    String table,
    String column,
    String value,
  ) sync* {
    _check(table);
    if (!_db
        .select('PRAGMA table_info("$table")')
        .any((r) => r['name'] == column)) {
      throw ArgumentError.value(column);
    }
    final statement = _db.prepare(
      'SELECT * FROM "$table" WHERE "$column"=? ORDER BY rowid',
    );
    try {
      final cursor = statement.selectCursor([value]);
      while (cursor.moveNext()) {
        yield Map<String, Object?>.from(cursor.current);
      }
    } finally {
      statement.close();
    }
  }

  @override
  Map<String, Object?>? rowByKey(String table, String column, String value) {
    _check(table);
    if (!_db
        .select('PRAGMA table_info("$table")')
        .any((r) => r['name'] == column)) {
      throw ArgumentError.value(column);
    }
    final rows = _db.select(
      'SELECT * FROM "$table" WHERE "$column"=? LIMIT 2',
      [value],
    );
    if (rows.length > 1) throw StateError('Clave no única.');
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  @override
  Map<String, Object?>? event(String id) {
    final r = _db.select('SELECT * FROM events WHERE event_id=?', [id]);
    return r.isEmpty ? null : Map<String, Object?>.from(r.single);
  }

  @override
  List<Map<String, Object?>> get foreignKeyViolations => _db
      .select('SELECT * FROM pragma_foreign_key_check LIMIT 200')
      .map((r) => Map<String, Object?>.from(r))
      .toList();
  @override
  void close() => _db.close();
}
