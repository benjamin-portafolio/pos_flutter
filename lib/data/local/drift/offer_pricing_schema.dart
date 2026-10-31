import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'recognized_schema_v8.dart';

/// Aditiva sobre la huella completa capturada; nunca se reescriben eventos.
const offerPricingColumns = <String, Map<String, String>>{
  'product_variants': {
    'offer_price_minor':
        "INTEGER NULL CHECK (offer_price_minor IS NULL OR (typeof(offer_price_minor) = 'integer' AND offer_price_minor BETWEEN 1 AND 9007199254740991 AND offer_price_minor <= sale_price_minor))",
  },
  'sales': {
    'pricing_contract_version':
        'INTEGER NULL CHECK (pricing_contract_version IS NULL OR pricing_contract_version = 2)',
    'pricing_mode':
        "TEXT NULL CHECK (pricing_mode IS NULL OR pricing_mode IN ('normal','offer'))",
  },
  'sale_items': {
    'price_snapshot_version': 'INTEGER NULL',
    'normal_price_minor_snapshot': 'INTEGER NULL',
    'offer_price_minor_snapshot': 'INTEGER NULL',
    'effective_price_source': 'TEXT NULL',
    'price_selection': 'TEXT NULL',
    'price_configuration_event_id': 'TEXT NULL',
  },
};

const _lineValid = """
(NEW.price_snapshot_version IS NULL AND NEW.normal_price_minor_snapshot IS NULL
 AND NEW.offer_price_minor_snapshot IS NULL AND NEW.effective_price_source IS NULL
 AND NEW.price_selection IS NULL AND NEW.price_configuration_event_id IS NULL)
OR (NEW.price_snapshot_version IS NOT NULL AND NEW.price_snapshot_version = 2
 AND typeof(NEW.normal_price_minor_snapshot) = 'integer'
 AND NEW.normal_price_minor_snapshot BETWEEN 1 AND 9007199254740991
 AND (NEW.offer_price_minor_snapshot IS NULL OR (typeof(NEW.offer_price_minor_snapshot) = 'integer'
 AND NEW.offer_price_minor_snapshot BETWEEN 1 AND NEW.normal_price_minor_snapshot))
 AND NEW.effective_price_source IS NOT NULL AND NEW.effective_price_source IN ('normal','offer')
 AND NEW.price_selection IS NOT NULL AND NEW.price_selection = 'inherit'
 AND NEW.price_configuration_event_id IS NOT NULL AND length(NEW.price_configuration_event_id) = 36
 AND ((NEW.effective_price_source = 'normal' AND NEW.unit_price_minor = NEW.normal_price_minor_snapshot)
 OR (NEW.effective_price_source = 'offer' AND NEW.offer_price_minor_snapshot IS NOT NULL
 AND NEW.unit_price_minor = NEW.offer_price_minor_snapshot)))
""";
const _saleValid = """
(NEW.pricing_contract_version IS NULL AND NEW.pricing_mode IS NULL)
OR (NEW.pricing_contract_version IS NULL AND NEW.status = 'borrador' AND NEW.pricing_mode = 'normal')
OR (NEW.pricing_contract_version IS NOT NULL AND NEW.pricing_contract_version = 2
 AND NEW.pricing_mode IS NOT NULL AND NEW.pricing_mode IN ('normal','offer'))
""";
final offerPricingTriggers = <String>[
  for (final operation in ['INSERT', 'UPDATE'])
    for (final table in ['sale_items', 'sales'])
      'CREATE TRIGGER offer_v2_${table}_${operation.toLowerCase()} BEFORE $operation ON $table '
          'WHEN NOT (${table == 'sale_items' ? _lineValid : _saleValid}) '
          "BEGIN SELECT RAISE(ABORT, 'Contrato de precio incoherente'); END",
];

String _normalize(String sql) => sql
    .replaceAll(RegExp('if not exists ', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
Map<String, String> _fingerprint(Database db) => {
  for (final row in db.select(
    "SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    row['name'] as String: sha256
        .convert(utf8.encode(_normalize(row['sql'] as String)))
        .toString(),
};
bool _same(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

// Construye la huella destino desde DDL reconocido, sin aceptar columnas sueltas.
Map<String, String>? _migratedFingerprint;
Map<String, String> _expectedMigrated() {
  return _migratedFingerprint ??= _buildExpected();
}

Map<String, String> _buildExpected() {
  final db = sqlite3.openInMemory();
  try {
    // DDL verificable del esquema anterior, no datos de ninguna terminal.
    for (final sql in recognizedSchemaV8Sql) {
      db.execute(sql);
    }
    _addOfferSchema(db);
    return _fingerprint(db);
  } finally {
    db.close();
  }
}

bool hasRecognizedOfferSchema(Database db) =>
    db.select('PRAGMA user_version').single['user_version'] == 9 &&
    (_same(_fingerprint(db), _expectedMigrated()) ||
        _same(_fingerprint(db), recognizedFreshSchemaV9));

void _addOfferSchema(Database db) {
  for (final table in offerPricingColumns.entries) {
    for (final column in table.value.entries) {
      db.execute(
        'ALTER TABLE ${table.key} ADD COLUMN ${column.key} ${column.value}',
      );
    }
  }
  for (final sql in offerPricingTriggers) {
    db.execute(sql);
  }
}

/// Abre primero en solo lectura: desconocidos conservan incluso WAL/SHM.
Future<void> prepareAppDatabase(
  File file, {
  void Function(Database)? afterAlterForTesting,
}) async {
  if (!await file.exists()) return;
  // SQLite puede escribir marcas de lectores en SHM incluso en readOnly.
  // Inspeccionar una copia con sus sidecars mantiene el desconocido byte a byte.
  final probeDir = await Directory.systemTemp.createTemp('pos-schema-probe-');
  final probe = File('${probeDir.path}/database');
  bool current;
  bool legacy;
  try {
    for (final suffix in ['', '-wal', '-shm']) {
      final source = File('${file.path}$suffix');
      if (await source.exists()) await source.copy('${probe.path}$suffix');
    }
    final inspection = sqlite3.open(probe.path, mode: OpenMode.readOnly);
    try {
      current = hasRecognizedOfferSchema(inspection);
      legacy =
          inspection.select('PRAGMA user_version').single['user_version'] ==
              8 &&
          _same(_fingerprint(inspection), recognizedSchemaV8);
    } finally {
      inspection.close();
    }
  } finally {
    await probeDir.delete(recursive: true);
  }
  if (current) return;
  if (!legacy) {
    throw StateError(
      'Esquema SQLite no reconocido. Archivo conservado; se requiere una ruta de migración acreditada.',
    );
  }
  final db = sqlite3.open(file.path);
  try {
    db.execute('BEGIN IMMEDIATE');
    try {
      if (db.select('PRAGMA user_version').single['user_version'] != 8 ||
          !_same(_fingerprint(db), recognizedSchemaV8)) {
        throw StateError('El esquema cambió durante la apertura.');
      }
      _validate(db);
      _addOfferSchema(db);
      afterAlterForTesting?.call(db);
      db.execute('PRAGMA user_version = 9');
      _validate(db);
      if (!hasRecognizedOfferSchema(db)) {
        throw StateError('Esquema migrado inesperado.');
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    db.close();
  }
}

void _validate(Database db) {
  if (db.select('PRAGMA integrity_check').single.values.single != 'ok' ||
      db.select('PRAGMA foreign_key_check').isNotEmpty) {
    throw StateError('Base inválida; no se modificará.');
  }
}
