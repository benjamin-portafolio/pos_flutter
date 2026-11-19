import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

/// Exporta solo estructura desde una base efímera; nunca abre la base del usuario.
void main() {
  test('exporta el esquema ER desde una base efímera', () async {
    const output = String.fromEnvironment('ER_SCHEMA_OUTPUT');
    final outputPath = output.isEmpty
        ? '${Directory.systemTemp.path}/pos_sqlite_er.json'
        : output;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      final tables = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get();
      final result = <Map<String, Object?>>[];
      for (final table in tables) {
        final name = table.read<String>('name');
        final quoted = '"${name.replaceAll('"', '""')}"';
        Future<List<Map<String, Object?>>> pragma(String kind) async =>
            (await db.customSelect('PRAGMA $kind($quoted)').get())
                .map((row) => row.data)
                .toList();
        final indexes = await db
            .customSelect(
              "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
              'AND tbl_name = ? ORDER BY name',
              variables: [Variable<String>(name)],
            )
            .get();
        final indexDetails = <Map<String, Object?>>[];
        for (final index in await pragma('index_list')) {
          final indexName = index['name'] as String;
          final indexQuoted = '"${indexName.replaceAll('"', '""')}"';
          final columns = await db
              .customSelect('PRAGMA index_info($indexQuoted)')
              .get();
          indexDetails.add({
            ...index,
            'columns': columns.map((row) => row.data['name']).toList(),
          });
        }
        result.add({
          'name': name,
          'ddl': table.read<String>('sql'),
          'columns': await pragma('table_info'),
          'foreign_keys': await pragma('foreign_key_list'),
          'indexes': indexes.map((row) => row.data).toList(),
          'index_details': indexDetails,
        });
      }
      final encoded = const JsonEncoder.withIndent('  ').convert({
        'source': 'AppDatabase.forTesting(NativeDatabase.memory())',
        'schema_version': db.schemaVersion,
        'tables': result,
      });
      await File(outputPath).writeAsString('$encoded\n');
      stdout.writeln(
        'Exportadas ${result.length} tablas; esquema v${db.schemaVersion}.',
      );
    } finally {
      await db.close();
    }
  });
}
