import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import '../../../application/recovery/baseline_bootstrap_installer.dart';
import '../../../application/recovery/recovery_event_contract.dart';
import '../../../application/recovery/recovery_json.dart';
import '../../../application/recovery/recovery_logical_schema.dart';
import '../drift/app_database.dart';
import '../drift/current_database_schema.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'recovery_bootstrap_row_mapper.dart';
import 'bootstrap_download_cache.dart';
import '../drift/drift_customer_credit_store.dart';

/// Materializa únicamente las familias acreditadas por el validador remoto S4.
/// Base nueva v10 y privada; un fallo nunca reemplaza una base ya instalada.
class SqliteBaselineBootstrapInstaller implements BaselineBootstrapInstaller {
  SqliteBaselineBootstrapInstaller(this.privateDirectory);
  final Directory privateDirectory;
  @override
  Future<String> install(
    Map<String, Object?> descriptor,
    Future<List<int>> Function(int index) download,
  ) async {
    final chunks = descriptor['chunks'];
    final h = int.tryParse('${descriptor['baseline_high_watermark']}');
    if (chunks is! List ||
        chunks.length > 100000 ||
        h == null ||
        h < 0 ||
        h >= 9007199254740991) {
      throw const FormatException('Descriptor bootstrap inválido.');
    }
    await privateDirectory.create(recursive: true);
    final cache = BootstrapDownloadCache(privateDirectory, descriptor);
    final installed = File('${cache.directory.path}/installed.json');
    if (await installed.exists()) {
      final record = Map<String, Object?>.from(
        jsonDecode(await installed.readAsString()) as Map,
      );
      final previous = File(record['database_path'] as String);
      if (await previous.exists() &&
          (await sha256.bind(previous.openRead()).first).toString() ==
              record['sha256']) {
        return previous.path;
      }
      throw StateError(
        'La base bootstrap conservada cambió. No se sustituye ni se reutiliza como vacía.',
      );
    }
    final staging = await privateDirectory.createTemp('bootstrap-');
    final file = File('${staging.path}/database.sqlite');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    var complete = false;
    var closed = false;
    try {
      final counts = <String, int>{};
      final supported = RecoveryLogicalSchema.keys.keys.toSet();
      final expected = Map<String, Object?>.from(descriptor['summary'] as Map);
      final expectedHashes = Map<String, Object?>.from(
        expected['row_digests'] as Map,
      );
      if (expectedHashes.keys.any((entity) => !supported.contains(entity))) {
        throw const FormatException('Resumen bootstrap incompatible.');
      }
      final results = {for (final e in expectedHashes.keys) e: _DigestResult()};
      final hashes = {
        for (final e in results.entries)
          e.key: sha256.startChunkedConversion(e.value),
      };
      final lastKeys = <String, List<String>>{};
      await db.customStatement('PRAGMA temp_store=FILE');
      await db.customStatement(
        'CREATE TEMP TABLE bootstrap_rows(entity TEXT NOT NULL,row_key TEXT NOT NULL,row_data TEXT NOT NULL,PRIMARY KEY(entity,row_key)) WITHOUT ROWID',
      );
      Future<Map<String, Object?>?> lookup(
        String entity,
        List<String> key,
      ) async {
        final rows = await db
            .customSelect(
              'SELECT row_data FROM bootstrap_rows WHERE entity=? AND row_key=?',
              variables: [Variable(entity), Variable(recoveryCanonical(key))],
            )
            .get();
        return rows.isEmpty
            ? null
            : Map<String, Object?>.from(
                jsonDecode(rows.single.read<String>('row_data')) as Map,
              );
      }

      final mapper = RecoveryBootstrapRowMapper(
        convert: _convert,
        lookup: lookup,
      );
      await db.transaction(() async {
        await db.customStatement('PRAGMA defer_foreign_keys=ON');
        // Es una base nueva, sembrada por AppDatabase. Las unidades se contrastan.
        for (var i = 0; i < chunks.length; i++) {
          final c = Map<String, Object?>.from(chunks[i] as Map);
          if (c['index'] != i ||
              c['bytes'] is! int ||
              (c['bytes'] as int) > 4194304 ||
              c['rows'] is! int ||
              (c['rows'] as int) < 1 ||
              (c['rows'] as int) > 1000) {
            throw const FormatException('Lote bootstrap inválido.');
          }
          final bytes = await cache.chunk(c, download);
          if (bytes.length != c['bytes'] ||
              sha256.convert(bytes).toString() != c['sha256']) {
            throw const FormatException('Integridad bootstrap inválida.');
          }
          final text = utf8.decode(bytes);
          if (!text.endsWith('\n')) throw const FormatException('Falta LF.');
          final lines = text.substring(0, text.length - 1).split('\n');
          if (lines.length != c['rows']) {
            throw const FormatException('Cantidad distinta.');
          }
          for (final line in lines) {
            final envelope = Map<String, Object?>.from(jsonDecode(line) as Map);
            if (recoveryCanonical(envelope) != line ||
                envelope.length != 2 ||
                envelope['entity'] != c['entity']) {
              throw const FormatException('Fila bootstrap incompatible.');
            }
            final entity = envelope['entity'] as String;
            if (!supported.contains(entity) && entity != 'event_provenance') {
              throw UnsupportedError(
                'Familia bootstrap no acreditada: $entity',
              );
            }
            final row = Map<String, Object?>.from(envelope['row'] as Map);
            final key = RecoveryLogicalSchema.key(entity, row);
            final last = lastKeys[entity];
            if (last != null && RecoveryLogicalSchema.compare(last, key) >= 0) {
              throw const FormatException('Identidad duplicada/desordenada.');
            }
            lastKeys[entity] = key;
            counts[entity] = (counts[entity] ?? 0) + 1;
            final hash = hashes[entity];
            // Descriptors anteriores a la ampliación S4 no resumían sidecars.
            // Sus bytes todavía están ligados al digest de cada chunk.
            if (hash == null && entity != 'event_provenance') {
              throw const FormatException('Entidad sin resumen.');
            }
            hash?.add(utf8.encode('${recoveryCanonical(row)}\n'));
            await db.customStatement(
              'INSERT INTO bootstrap_rows VALUES(?,?,?)',
              [entity, recoveryCanonical(key), recoveryCanonical(row)],
            );
          }
        }
        for (final e in hashes.entries) {
          e.value.close();
          if (results[e.key]!.value != expectedHashes[e.key]) {
            throw FormatException('Identidades/contenido distintos: ${e.key}');
          }
        }
        for (final entity in expectedHashes.keys) {
          if ('${counts[entity] ?? 0}' != expected[entity]) {
            throw FormatException('Conteo distinto: $entity');
          }
        }
        for (final entity in [
          'events',
          'event_refs',
          'units',
          'categories',
          'espacios',
          'suppliers',
          'clientes',
          'inventory_items',
          'products',
          'product_variants',
          'recipe_components',
          'variant_suppliers',
          'variant_inventory_memory',
          'sales',
          'sale_items',
          'sale_payments',
          'credit_sales',
          'customer_payments',
          'financial_categories',
          'financial_entries',
          'account_balance_baselines',
          'cash_sessions',
          'sale_adjustments',
          'sale_adjustment_lines',
          'sale_credit_reductions',
          'inventory_movements',
          'inventory_balances',
          'sale_reconciliation_effects',
          'cash_movements',
          'credit_allocations',
          'sale_adjustment_evidence',
          'sale_delivery_incidents',
          'inventory_item_discards',
        ]) {
          var after = '';
          while (true) {
            final page = await db
                .customSelect(
                  'SELECT row_key,row_data FROM bootstrap_rows WHERE entity=? AND row_key>? ORDER BY row_key LIMIT 200',
                  variables: [Variable(entity), Variable(after)],
                )
                .get();
            if (page.isEmpty) break;
            for (final entry in page) {
              after = entry.read<String>('row_key');
              final row = Map<String, Object?>.from(
                jsonDecode(entry.read<String>('row_data')) as Map,
              );
              for (final mapped in await mapper.map(entity, row)) {
                final local = mapped.values;
                if (entity == 'units') {
                  final actual = await db
                      .customSelect(
                        'SELECT * FROM units WHERE unit_id=?',
                        variables: [Variable(local['unit_id'] as String)],
                      )
                      .get();
                  if (actual.length != 1 ||
                      recoveryCanonical(actual.single.data) !=
                          recoveryCanonical(local)) {
                    throw const FormatException(
                      'Unidad distinta del seed acreditado.',
                    );
                  }
                  continue;
                }
                await db.customStatement(
                  'INSERT INTO "${mapped.table}" (${local.keys.map((k) => '"$k"').join(',')}) VALUES (${local.keys.map((_) => '?').join(',')})',
                  local.values.toList(),
                );
              }
            }
          }
        }
        final beforeAllocations = await db
            .customSelect(
              'SELECT * FROM credit_allocations ORDER BY payment_id,credit_id',
            )
            .get();
        var customerAfter = '';
        while (true) {
          final customers = await db
              .customSelect(
                'SELECT id FROM clientes WHERE id>? ORDER BY id LIMIT 200',
                variables: [Variable(customerAfter)],
              )
              .get();
          if (customers.isEmpty) break;
          for (final c in customers) {
            customerAfter = c.read<String>('id');
            await DriftCustomerCreditStore(db).rebuild(customerAfter);
          }
        }
        final afterAllocations = await db
            .customSelect(
              'SELECT * FROM credit_allocations ORDER BY payment_id,credit_id',
            )
            .get();
        if (recoveryCanonical(beforeAllocations.map((r) => r.data).toList()) !=
            recoveryCanonical(afterAllocations.map((r) => r.data).toList())) {
          throw const FormatException('Asignaciones FIFO bootstrap distintas.');
        }
        var cursor = 0;
        while (true) {
          final page =
              await (db.select(db.events)
                    ..where((t) => t.localSequence.isBiggerThanValue(cursor))
                    ..orderBy([(t) => OrderingTerm.asc(t.localSequence)])
                    ..limit(500))
                  .get();
          if (page.isEmpty) break;
          for (final event in page) {
            cursor = event.localSequence;
            if (event.serverSequence == null ||
                event.serverSequence! <= 0 ||
                event.serverSequence! > h) {
              throw const FormatException(
                'Secuencia fuera del corte bootstrap.',
              );
            }
            final payload = Map<String, Object?>.from(
              jsonDecode(event.payload) as Map,
            );
            if (event.deliveryStatus != 'delivered') continue;
            for (final dependency in RecoveryEventContract.dependencies(
              event.eventType,
              payload,
            )) {
              final prior = await db.eventDao.obtenerEventoPorId(dependency);
              if (prior == null || prior.deliveryStatus != 'delivered') {
                throw const FormatException(
                  'Dependencia del bootstrap ausente.',
                );
              }
            }
          }
        }
        for (final table in [
          'suppliers',
          'clientes',
          'inventory_items',
          'financial_categories',
          'financial_entries',
          'customer_payments',
          'account_balance_baselines',
        ]) {
          final invalid = await db
              .customSelect(
                'SELECT p.id FROM "$table" p LEFT JOIN events c ON c.event_id=p.created_event_id LEFT JOIN events e ON e.event_id=p.last_event_id WHERE c.delivery_status IS NOT \'delivered\' OR e.delivery_status IS NOT \'delivered\' OR e.server_sequence IS NOT p.last_server_sequence LIMIT 1',
              )
              .get();
          if (invalid.isNotEmpty) {
            throw FormatException('Procedencia local inválida: $table');
          }
        }
        final invalidStock = await db.customSelect('''
          SELECT b.inventory_item_id FROM inventory_balances b
          LEFT JOIN inventory_items i ON i.id=b.inventory_item_id
          LEFT JOIN events e ON e.event_id=b.last_event_id
          WHERE i.id IS NULL OR e.delivery_status IS NOT 'delivered'
            OR e.server_sequence IS NOT b.last_server_sequence
            OR b.quantity_on_hand_atomic IS NOT ((SELECT coalesce(sum(m.quantity_delta_atomic),0) FROM inventory_movements m WHERE m.inventory_item_id=b.inventory_item_id)+(SELECT coalesce(sum(r.delta),0) FROM sale_reconciliation_effects r WHERE r.ledger='stock' AND r.target_id=b.inventory_item_id))
            OR b.quantity_available_atomic IS NOT b.quantity_on_hand_atomic LIMIT 1
        ''').get();
        if (invalidStock.isNotEmpty) {
          throw const FormatException(
            'Libro de inventario bootstrap incompatible.',
          );
        }
        await db.customStatement(
          'INSERT INTO sync_checkpoints(checkpoint_id,last_full_pull_server_sequence,last_preflight_server_sequence) VALUES(?,?,?)',
          ['full_pull', h, h],
        );
        await db.customStatement(
          'UPDATE recovery_local_state SET server_instance_id=?,generation_id=?,dataset_id=? WHERE singleton=1',
          [
            descriptor['server_instance_id'],
            descriptor['generation_id'],
            descriptor['dataset_id'],
          ],
        );
        if ((await db.customSelect('PRAGMA foreign_key_check').get())
            .isNotEmpty) {
          throw StateError('Dependencia SQLite ausente.');
        }
        if ((await db.customSelect('PRAGMA integrity_check').get())
                .single
                .data
                .values
                .single !=
            'ok') {
          throw StateError('SQLite no íntegro.');
        }
      });
      await db.close();
      closed = true;
      final verify = sqlite.sqlite3.open(
        file.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        if (!hasCurrentAppDatabaseSchema(verify)) {
          throw StateError('Huella SQLite desconocida.');
        }
      } finally {
        verify.close();
      }
      // No configuration points at this file before all checks and SQLite close.
      await File(
        '${staging.path}/bootstrap.json',
      ).writeAsString(recoveryCanonical(descriptor), flush: true);
      await cache.directory.create(recursive: true);
      final record = <String, Object?>{
        'database_path': file.path,
        'sha256': (await sha256.bind(file.openRead()).first).toString(),
      };
      final temporary = File('${cache.directory.path}/installed.tmp');
      await temporary.writeAsString(recoveryCanonical(record), flush: true);
      await temporary.rename(installed.path);
      complete = true;
      return file.path;
    } finally {
      if (!complete) {
        if (!closed) await db.close();
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    }
  }

  Object? _convert(String field, String type, Object? value) {
    if (value == null) return null;
    switch (type) {
      case 'boolean':
        if (value is! bool) throw FormatException('Booleano inválido: $field');
        return value ? 1 : 0;
      case 'numeric':
        if (value is! String ||
            !RegExp(r'^(0|-?[1-9][0-9]*)$').hasMatch(value) ||
            value.length > 100) {
          throw FormatException('Decimal inválido: $field');
        }
        return value;
      case 'bigint':
        if (value is! String ||
            !RegExp(r'^(0|-?[1-9][0-9]*)$').hasMatch(value)) {
          throw FormatException('Decimal inválido: $field');
        }
        final number = int.parse(value);
        if (number.abs() > 9007199254740991) {
          throw FormatException('Rango inválido: $field');
        }
        return number;
      case 'integer':
        if (value is! int || value.abs() > 2147483647) {
          throw FormatException('Entero inválido: $field');
        }
        return value;
      case 'timestamptz':
        if (value is! String ||
            !RegExp(
              r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$',
            ).hasMatch(value)) {
          throw FormatException('Instante inválido: $field');
        }
        final date = DateTime.parse(value);
        if (date.toIso8601String() != value) {
          throw FormatException('Fecha inválida: $field');
        }
        return date.millisecondsSinceEpoch ~/ 1000;
      case 'jsonb':
        return jsonEncode(value);
      case 'uuid':
        if (value is! String ||
            !RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ).hasMatch(value)) {
          throw FormatException('UUID inválido: $field');
        }
        return value;
      default:
        if (value is! String) throw FormatException('Texto inválido: $field');
        return value;
    }
  }
}

class _DigestResult implements Sink<Digest> {
  String? value;
  @override
  void add(Digest data) => value = data.toString();
  @override
  void close() {}
}
