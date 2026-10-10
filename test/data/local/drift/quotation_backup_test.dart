import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../support/quotation_contract_fixtures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/cotizaciones/guardar_cotizacion_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_status.dart';
import '../../../support/quotation_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> export(String name, Object value, {File? database}) async {
    final output = Platform.environment['POS_QUOTATION_VERIFICATION_DIR'];
    if (output == null) return;
    await Directory(output).create(recursive: true);
    await File(
      '$output/$name.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(value));
    if (database != null) await database.copy('$output/$name.sqlite');
  }

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pos_quotation_backup_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temp.delete(recursive: true);
  });

  for (final mode in AppMode.values) {
    for (final status in QuotationStatus.values) {
      test(
        'C06/C28/C34: reinicio y respaldo/restauración $mode / $status',
        () async {
          var h = QuotationHarness(database: AppDatabase(), mode: mode);
          await h.seed();
          await h.add();
          await h.add(QuotationHarness.measuredId);
          final command = await h.intent();
          await h.service().guardar(command);
          if (status == QuotationStatus.disponible) {
            await h.drafts.limpiar(
              LimpiarVentaBorradorCommand(
                saleId: command.saleId,
                expectedDraftEventId: command.expectedDraftEventId,
              ),
            );
          } else if (status == QuotationStatus.vendida) {
            final confirmation = await h.confirm();
            await h.db.eventDao.actualizarEstadoSincronizacion(
              confirmation,
              mode == AppMode.standalone ? 'not_required' : 'rejected',
            );
          }
          await h.db.customStatement(
            'CREATE TABLE quotation_restart_marker(id TEXT)',
          );
          final before = await h.contents();
          await h.dispose();
          h = QuotationHarness(database: AppDatabase(), mode: mode);
          expect(
            await h.contents(),
            before,
          ); // Arranque normal no reinicia esquema actual.
          expect(
            (await h.repository.findById(command.quotationId))!.status,
            status,
          );
          final snapshot = await DriftDatabaseSnapshotService(
            db: h.db,
            stateReader: DriftDatabaseStateReader(db: h.db),
          ).createSnapshot();
          try {
            final raw = sqlite.sqlite3.open(snapshot.file.path);
            expect(
              raw.select('PRAGMA integrity_check').single.values.single,
              'ok',
            );
            expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
            expect(raw.select('SELECT * FROM quotations'), hasLength(1));
            expect(raw.select('SELECT * FROM quotation_items'), hasLength(2));
            raw.close();
            await h
                .add(); // Modificación después del snapshot que debe desaparecer.
            await DriftDatabaseRestoreService(
              db: h.db,
            ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
            h.config.dispose();
            h = QuotationHarness(database: AppDatabase(), mode: mode);
            expect(await h.contents(), before);
            final quotation = (await h.repository.findById(
              command.quotationId,
            ))!;
            expect(quotation.status, status);
            expect(quotation.currentSaleId, command.saleId);
            expect(quotation.issuedAtLocal, command.issuedAtLocal);
            expect(quotation.items.last.measuredQuantityAtomic, 750);
            final retry = await h.service().guardar(
              GuardarCotizacionCommand(
                saleId: command.saleId,
                expectedDraftEventId: command.expectedDraftEventId,
                quotationId: command.quotationId,
                eventId: command.eventId,
                issuedAtLocal: command.issuedAtLocal,
              ),
            );
            expect(retry.eventId, command.eventId);
            expect(retry.issuedAtLocal, command.issuedAtLocal);
            expect(
              (await h.db.eventDao.obtenerEventoPorId(
                command.eventId,
              ))!.deliveryStatus,
              'not_required',
            );
            expect(await h.contents(), before);
            expect(await appDatabaseShouldPreserveRestoredDatabase(), isTrue);
            await h.dispose();
            h = QuotationHarness(database: AppDatabase(), mode: mode);
            expect(
              await h.contents(),
              before,
            ); // Reinicio posterior al restore conserva todo.
            expect(
              await h.db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE name = 'quotation_restart_marker'",
                  )
                  .get(),
              hasLength(1),
            );
            expect(h.db.schemaVersion, 8);
            await export('backup-${mode.name}-${status.name}', {
              'schema_version': h.db.schemaVersion,
              'status': status.name,
              'sha256': snapshot.sha256,
              'contents': before,
              'normal_restart_preserved': true,
              'restored_and_second_restart_preserved': true,
              'protected': await appDatabaseShouldPreserveRestoredDatabase(),
              'integrity_check': 'ok',
              'foreign_key_check': [],
            }, database: snapshot.file);
          } finally {
            await h.dispose();
            await snapshot.file.parent.delete(recursive: true);
          }
        },
      );
    }
  }

  for (final restored in [false, true]) {
    for (final missing in ['tables', 'index', 'column']) {
      test(
        'esquema previo sin $missing: reset o respaldo protegido ($restored)',
        () async {
          final initial = AppDatabase();
          if (missing == 'tables') {
            await initial.customStatement('DROP TABLE quotation_items');
            await initial.customStatement('DROP TABLE quotations');
          } else if (missing == 'index') {
            await initial.customStatement(
              'DROP INDEX ux_quotations_current_sale',
            );
          } else {
            await initial.customStatement(
              'ALTER TABLE quotation_items DROP COLUMN variant_name_snapshot',
            );
          }
          await initial.customStatement(
            'CREATE TABLE retained_quotation_marker(id TEXT)',
          );
          await initial.close();
          if (restored) await markAppDatabaseAsRestored();
          final reopened = AppDatabase();
          if (restored) {
            await expectLater(
              reopened.select(reopened.quotations).get(),
              throwsStateError,
            );
            await expectLater(reopened.close(), throwsStateError);
            final raw = sqlite.sqlite3.open((await appDatabaseFile()).path);
            expect(
              raw.select(
                "SELECT name FROM sqlite_master WHERE name = 'retained_quotation_marker'",
              ),
              isNotEmpty,
            );
            raw.close();
          } else {
            expect(await reopened.select(reopened.quotations).get(), isEmpty);
            expect(
              await reopened
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE name = 'retained_quotation_marker'",
                  )
                  .get(),
              isEmpty,
            );
            expect(reopened.schemaVersion, 8);
            await reopened.close();
          }
        },
      );
    }
  }
  for (final restored in [false, true]) {
    final forbidden =
        quotationFixture('esquema-compatibilidad')['forbidden_columns'] as Map;
    for (final table in forbidden.entries) {
      for (final column in table.value as List) {
        test(
          'P20/P22: esquema 8 superconjunto con ${table.key}.$column, protegido=$restored',
          () async {
            final initial = AppDatabase();
            await initial.customStatement(
              'ALTER TABLE ${table.key} ADD COLUMN $column',
            );
            await initial.customStatement(
              'CREATE TABLE retained_legacy_marker(id TEXT)',
            );
            await initial.customStatement(
              "INSERT INTO retained_legacy_marker VALUES ('whole database')",
            );
            await initial.customStatement(
              "INSERT INTO events(event_id,aggregate_type,aggregate_id,event_type,device_id,user_id,created_at_local,payload) VALUES ('legacy','quotation','legacy','cotizacion_guardada','device','user',1,?)",
              [
                jsonEncode({'unit_price_minor': 100}),
              ],
            );
            await initial.close();
            final file = await appDatabaseFile();
            if (restored) await markAppDatabaseAsRestored();
            final hash = sha256.convert(await file.readAsBytes()).toString();
            final reopened = AppDatabase();
            if (restored) {
              await expectLater(
                reopened.select(reopened.quotations).get(),
                throwsStateError,
              );
              await expectLater(reopened.close(), throwsStateError);
              expect(sha256.convert(await file.readAsBytes()).toString(), hash);
              expect(await appDatabaseShouldPreserveRestoredDatabase(), isTrue);
            } else {
              expect(await reopened.select(reopened.quotations).get(), isEmpty);
              expect(await reopened.select(reopened.events).get(), isEmpty);
              expect(
                await reopened
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE name='retained_legacy_marker'",
                    )
                    .get(),
                isEmpty,
              );
              expect(
                (await reopened
                        .customSelect('PRAGMA table_info(${table.key})')
                        .get())
                    .map((r) => r.data['name']),
                isNot(contains(column)),
              );
              expect(reopened.schemaVersion, 8);
              await reopened.customStatement(
                'CREATE TABLE new_restart_marker(id TEXT)',
              );
              await reopened.close();
              final second = AppDatabase();
              expect(
                await second
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE name='new_restart_marker'",
                    )
                    .get(),
                hasLength(1),
              );
              await second.close();
            }
          },
        );
      }
    }
  }

  for (final restored in [false, true]) {
    test(
      'P20/P22: siete columnas antiguas y restore real, protegido=$restored',
      () async {
        final h = QuotationHarness(database: AppDatabase());
        await h.seed();
        await h.add();
        await h.service().guardar(await h.intent());
        final forbidden =
            quotationFixture('esquema-compatibilidad')['forbidden_columns']
                as Map;
        for (final table in forbidden.entries) {
          for (final column in table.value as List) {
            await h.db.customStatement(
              'ALTER TABLE ${table.key} ADD COLUMN $column',
            );
          }
        }
        await h.db.customStatement(
          'CREATE TABLE legacy_closure_marker(value TEXT)',
        );
        await h.db.customStatement(
          "INSERT INTO legacy_closure_marker VALUES ('preserve protected legacy database')",
        );
        await h.db.customStatement(
          "INSERT INTO events(event_id,aggregate_type,aggregate_id,event_type,device_id,user_id,created_at_local,payload) VALUES ('legacy','quotation','legacy','cotizacion_guardada','device','user',1,?)",
          [
            jsonEncode({
              'copy': {
                'lines': [
                  {'unit_price_minor': 10000, 'total_minor': 20000},
                ],
              },
            }),
          ],
        );
        final snapshot = await DriftDatabaseSnapshotService(
          db: h.db,
          stateReader: DriftDatabaseStateReader(db: h.db),
        ).createSnapshot();
        try {
          if (restored) {
            // Restore rechaza ahora el esquema antiguo antes de reemplazarlo.
            // La protección de un archivo legado ya presente se verifica aparte.
            final currentFile = await appDatabaseFile();
            final currentHash = sha256
                .convert(await currentFile.readAsBytes())
                .toString();
            await expectLater(
              DriftDatabaseRestoreService(
                db: h.db,
              ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256),
              throwsStateError,
            );
            expect(
              sha256.convert(await currentFile.readAsBytes()).toString(),
              currentHash,
            );
            expect(await appDatabaseShouldPreserveRestoredDatabase(), isFalse);
            await markAppDatabaseAsRestored();
            await h.dispose();
          } else {
            await h.dispose();
          }
          final file = await appDatabaseFile();
          final beforeHash = sha256
              .convert(await file.readAsBytes())
              .toString();
          final reopened = AppDatabase();
          if (restored) {
            await expectLater(
              reopened.select(reopened.quotations).get(),
              throwsStateError,
            );
            await expectLater(reopened.close(), throwsStateError);
            expect(
              sha256.convert(await file.readAsBytes()).toString(),
              beforeHash,
            );
            expect(await appDatabaseShouldPreserveRestoredDatabase(), isTrue);
          } else {
            expect(await reopened.select(reopened.quotations).get(), isEmpty);
            expect(await reopened.select(reopened.products).get(), isEmpty);
            expect(await reopened.select(reopened.sales).get(), isEmpty);
            expect(await reopened.select(reopened.events).get(), isEmpty);
            await reopened.close();
          }
          final raw = sqlite.sqlite3.open(file.path);
          Map<String, Object?> result;
          try {
            expect(raw.select('PRAGMA user_version').single.values.single, 8);
            final columns = {
              for (final table in forbidden.keys)
                table.toString(): raw
                    .select('PRAGMA table_info($table)')
                    .map((r) => r['name'])
                    .toList(),
            };
            for (final table in forbidden.entries) {
              for (final column in table.value as List) {
                expect(columns[table.key]!.contains(column), restored);
              }
            }
            expect(
              raw
                  .select(
                    "SELECT name FROM sqlite_master WHERE name='legacy_closure_marker'",
                  )
                  .isNotEmpty,
              restored,
            );
            expect(
              raw
                  .select("SELECT * FROM events WHERE event_id='legacy'")
                  .isNotEmpty,
              restored,
            );
            result = {
              'schema_version': 8,
              'protected': restored,
              'columns': columns,
              'before_sha256': beforeHash,
              'after_sha256': sha256
                  .convert(await file.readAsBytes())
                  .toString(),
              'legacy_marker_preserved': restored,
              'legacy_event_preserved': restored,
              'whole_database_reset': !restored,
              'restore_service_executed': restored,
              'restore_rejected_before_replacement': restored,
              'startup_protection_marked_explicitly': restored,
            };
          } finally {
            raw.close();
          }
          await export(
            'legacy-all-columns-protected-$restored',
            result,
            database: file,
          );
        } finally {
          await snapshot.file.parent.delete(recursive: true);
        }
      },
    );
  }
}
