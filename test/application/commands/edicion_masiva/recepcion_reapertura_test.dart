import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:pos_flutter/application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/operacion_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/registro_operacion_masiva.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/current_database_schema.dart';
import 'package:pos_flutter/data/local/drift/drift_diario_edicion_masiva.dart';

import '../../../support/product_supplier_harness.dart';
import '../../../support/recepcion_masiva_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Cada reapertura usa un executor nuevo; los casos de apertura rechazada no
  // completan el contador de depuración de Drift, aunque sí cierran SQLite.
  final previousWarningSetting =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        previousWarningSetting,
  );
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pos_receipt_disk_');
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
    group(mode.name, () {
      late AppDatabase db;
      late ProductSupplierHarness h;
      EdicionMasivaCommandService service() => EdicionMasivaCommandService(
        DriftDiarioEdicionMasiva(
          db: db,
          config: h.tracking.config,
          context: h.tracking.context,
        ),
      );
      setUp(() {
        db = AppDatabase();
        h = ProductSupplierHarness(database: db, mode: mode);
      });
      tearDown(() async {
        await h.tracking.config.dispose();
        await db.close();
      });

      test(
        'M30/M31/M34 misma base reabre reservas y aplicadas sin ejecutar al arrancar',
        () async {
          final a = (await seedRecepcion(h, nombre: 'A'))[1];
          final b = (await seedRecepcion(h, nombre: 'B'))[1];
          final ops = await service().confirmar(
            batchId: 'reabrir',
            cambios: [
              cambioRecepcion(a, cantidad: 2),
              cambioRecepcion(b, cantidad: 3),
            ],
          );
          final result = await service().ejecutar(ops.first);
          final before = await fotoRecepcion(db);
          await db.close();
          db = AppDatabase();
          expect(await fotoRecepcion(db), before);
          final pending = await service().pendientes();
          expect(pending.single.estado, EstadoOperacionMasiva.confirmada);
          expect(pending.single.operacion.operationId, ops.last.operationId);
          expect(await fotoRecepcion(db), before);
          expect(
            (await service().ejecutar(
              OperacionEdicionMasiva.fromJson(ops.first.intencionJson),
            )).json,
            result.json,
          );
          expect(await fotoRecepcion(db), before);
          final continued = await service().continuar('reabrir');
          expect(continued.every((r) => r.error == null), isTrue);
          expect(continued.first.resultado!.json, result.json);
          final after = await fotoRecepcion(db);
          await db.close();
          db = AppDatabase();
          expect(await fotoRecepcion(db), after);
          expect(await service().pendientes(), isEmpty);
          expect(
            (await service().eventos(result)).map((e) => e.eventId),
            result.eventIds,
          );
        },
      );

      test(
        'M32 reapertura bajo otro modo conserva captura y bloquea continuación',
        () async {
          final f = (await seedRecepcion(h))[1];
          await service().confirmar(
            batchId: 'otro-modo',
            cambios: [cambioRecepcion(f, cantidad: 2)],
          );
          final before = await fotoRecepcion(db);
          await db.close();
          h.tracking.config.update(
            h.tracking.config.config.copyWith(
              mode: mode == AppMode.standalone
                  ? AppMode.serverSync
                  : AppMode.standalone,
            ),
          );
          db = AppDatabase();
          expect(await fotoRecepcion(db), before);
          expect((await service().pendientes()).single.operacion.modo, mode);
          final results = await service().continuar('otro-modo');
          expect(results.single.error, isA<StateError>());
          expect(await fotoRecepcion(db), before);
        },
      );

      test(
        'M33 snapshot/restore vigente conserva diario, catálogo, eventos y saldos',
        () async {
          final f = await seedRecepcion(h);
          final op = (await service().confirmar(
            batchId: 'backup',
            cambios: [
              cambioRecepcion(f[0], venta: 8000, cantidad: 250),
              cambioRecepcion(f[1], cantidad: 2),
            ],
          )).single;
          final result = await service().ejecutar(op);
          await service().confirmar(
            batchId: 'pendiente',
            cambios: [
              cambioRecepcion(
                await releerRecepcion(db, f[1].clave),
                cantidad: 3,
              ),
            ],
          );
          final before = await fotoRecepcion(db);
          final snapshot = await DriftDatabaseSnapshotService(
            db: db,
            stateReader: DriftDatabaseStateReader(db: db),
          ).createSnapshot();
          try {
            await db.delete(db.bulkEditOperations).go();
            await db.customStatement(
              'UPDATE inventory_balances SET quantity_on_hand_atomic=0',
            );
            await DriftDatabaseRestoreService(
              db: db,
            ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
            db = AppDatabase();
            expect(await fotoRecepcion(db), before);
            expect((await service().ejecutar(op)).json, result.json);
            expect(
              (await service().pendientes()).single.operacion.batchId,
              'pendiente',
            );
            expect(
              await db.customSelect('PRAGMA foreign_key_check').get(),
              isEmpty,
            );
            expect(
              (await db.customSelect('PRAGMA integrity_check').get())
                  .single
                  .data
                  .values
                  .single,
              'ok',
            );
            await db.close();
            db = AppDatabase();
            expect(await fotoRecepcion(db), before);
            expect(await appDatabaseShouldPreserveRestoredDatabase(), isTrue);
            expect(db.schemaVersion, 8);
          } finally {
            await snapshot.file.parent.delete(recursive: true);
          }
        },
      );

      for (final phase in ['before', 'after']) {
        test(
          'M30 cierre abrupto $phase commit y reapertura conserva cero o una aplicación',
          () async {
            final f = (await seedRecepcion(h))[1];
            final op = (await service().confirmar(
              batchId: 'crash',
              cambios: [cambioRecepcion(f, venta: 7000, cantidad: 2)],
            )).single;
            final before = await fotoRecepcion(db);
            final databaseFile = await appDatabaseFile();
            await db.close();
            final marker = File('${temp.path}/crash-marker.json');
            final process = await Process.start(
              'flutter',
              [
                'test',
                'test/support/recepcion_masiva_crash_worker.dart',
                '--reporter',
                'expanded',
              ],
              environment: {
                'POS_RECEIPT_DB': databaseFile.path,
                'POS_RECEIPT_MODE': mode.storageValue,
                'POS_RECEIPT_PHASE': phase,
                'POS_RECEIPT_MARKER': marker.path,
              },
            );
            final output = process.stdout.transform(utf8.decoder).join();
            final errors = process.stderr.transform(utf8.decoder).join();
            int? workerPid;
            try {
              final deadline = DateTime.now().add(const Duration(seconds: 60));
              while (!await marker.exists() &&
                  DateTime.now().isBefore(deadline)) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
              if (!await marker.exists()) {
                process.kill(ProcessSignal.sigkill);
                fail(
                  'El trabajador no llegó al punto de cierre: ${await output} ${await errors}',
                );
              }
              workerPid =
                  (jsonDecode(await marker.readAsString()) as Map)['pid']
                      as int;
              expect(Process.killPid(workerPid, ProcessSignal.sigkill), isTrue);
              await process.exitCode.timeout(const Duration(seconds: 15));
              db = AppDatabase();
              if (phase == 'before') {
                expect(await fotoRecepcion(db), before);
                expect(
                  (await service().pendientes()).single.estado,
                  EstadoOperacionMasiva.confirmada,
                );
              } else {
                expect(await service().pendientes(), isEmpty);
                expect(
                  (await releerRecepcion(
                    db,
                    f.clave,
                  )).entrada!.existenciaAtomic,
                  f.entrada!.existenciaAtomic + 2,
                );
                expect((await releerRecepcion(db, f.clave)).ventaMinor, 7000);
              }
              final result = await service().ejecutar(op);
              final applied = await fotoRecepcion(db);
              await db.close();
              db = AppDatabase();
              expect((await service().ejecutar(op)).json, result.json);
              expect(await fotoRecepcion(db), applied);
              expect(
                (await releerRecepcion(db, f.clave)).entrada!.existenciaAtomic,
                f.entrada!.existenciaAtomic + 2,
              );
            } finally {
              if (workerPid != null) {
                Process.killPid(workerPid, ProcessSignal.sigkill);
              }
              process.kill();
              await output;
              await errors;
            }
          },
          timeout: const Timeout(Duration(minutes: 2)),
        );
      }
    });
  }

  for (final missing in ['tabla', 'columna', 'indice']) {
    for (final protected in [false, true]) {
      test('M33 esquema sin $missing, protegido=$protected', () async {
        var db = AppDatabase();
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(id: 'sentinel', name: 'Conservar'),
            );
        await db.customStatement(switch (missing) {
          'tabla' => 'DROP TABLE bulk_edit_operations',
          'columna' =>
            'ALTER TABLE bulk_edit_operations RENAME COLUMN intent_json TO legacy_intent',
          _ => 'DROP INDEX ux_bulk_edit_batch_product',
        });
        await db.close();
        if (protected) await markAppDatabaseAsRestored();
        final file = await appDatabaseFile();
        final before = sha256.convert(await file.readAsBytes());
        final raw = sqlite.sqlite3.open(file.path);
        expect(hasCurrentAppDatabaseSchema(raw), isFalse);
        raw.close();
        db = AppDatabase();
        if (protected) {
          await expectLater(db.select(db.products).get(), throwsStateError);
          await expectLater(db.close(), throwsStateError);
          expect(sha256.convert(await file.readAsBytes()), before);
        } else {
          expect(await db.select(db.products).get(), isEmpty);
          expect(await db.select(db.bulkEditOperations).get(), isEmpty);
          expect(db.schemaVersion, 8);
          await db.close();
        }
      });
    }
  }

  test(
    'M33 restore rechaza respaldo sin diario antes de reemplazar base',
    () async {
      final db = AppDatabase();
      await db
          .into(db.products)
          .insert(ProductsCompanion.insert(id: 'sentinel', name: 'Conservar'));
      final before = await fotoRecepcion(db);
      final snapshot = await DriftDatabaseSnapshotService(
        db: db,
        stateReader: DriftDatabaseStateReader(db: db),
      ).createSnapshot();
      try {
        final raw = sqlite.sqlite3.open(snapshot.file.path);
        raw.execute('DROP TABLE bulk_edit_operations');
        raw.close();
        await expectLater(
          DriftDatabaseRestoreService(db: db).restoreSnapshot(
            snapshot.file,
            sha256: sha256
                .convert(await snapshot.file.readAsBytes())
                .toString(),
          ),
          throwsStateError,
        );
        expect(await fotoRecepcion(db), before);
        expect(await appDatabaseShouldPreserveRestoredDatabase(), isFalse);
      } finally {
        await db.close();
        await snapshot.file.parent.delete(recursive: true);
      }
    },
  );
}
