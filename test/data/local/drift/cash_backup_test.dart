import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import '../../../support/cash_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pos_cash_backup_');
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
  test(
    'snapshot/restore reales conservan corte, movimientos, entrega y siguiente apertura tras reinicio',
    () async {
      var h = CashHarness(database: AppDatabase(), mode: AppMode.standalone);
      final id = await h.open();
      await h.entry();
      final close = await h.cash.cerrar(
        CerrarCajaCommand(
          sessionId: id,
          countedMinor: 12400,
          notes: 'respaldo',
        ),
      );
      final snapshot = await DriftDatabaseSnapshotService(
        db: h.db,
        stateReader: DriftDatabaseStateReader(db: h.db),
      ).createSnapshot();
      await h.entry(drawer: false);
      await DriftDatabaseRestoreService(
        db: h.db,
      ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
      await h.config.dispose();
      h = CashHarness(database: AppDatabase(), mode: AppMode.standalone);
      final session = (await h.cashStore.find(id))!;
      expect(session.lastEventId, close);
      expect(session.close!.expectedMinor, '12500');
      expect(session.close!.differenceMinor, '-100');
      expect((await h.cashStore.movements(id)).length, 1);
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
      final next = await h.open();
      expect((await h.cashStore.find(next))!.previousCloseEventId, close);
      await h.dispose();
      h = CashHarness(database: AppDatabase(), mode: AppMode.standalone);
      expect((await h.cashStore.current(h.context.deviceId))!.id, next);
      await h.dispose();
      await snapshot.file.parent.delete(recursive: true);
    },
  );
  for (final restored in [false, true]) {
    test(
      'esquema sin caja: reset temporal o respaldo protegido ($restored)',
      () async {
        final initial = AppDatabase();
        await initial.customStatement('DROP TABLE cash_movements');
        await initial.customStatement('DROP TABLE cash_sessions');
        await initial.customStatement('CREATE TABLE retained_marker(id text)');
        await initial.close();
        if (restored) await markAppDatabaseAsRestored();
        final reopened = AppDatabase();
        if (restored) {
          await expectLater(
            reopened.select(reopened.cashSessions).get(),
            throwsStateError,
          );
          await expectLater(reopened.close(), throwsStateError);
          final raw = sqlite.sqlite3.open((await appDatabaseFile()).path);
          expect(
            raw.select(
              "SELECT name FROM sqlite_master WHERE name='retained_marker'",
            ),
            isNotEmpty,
          );
          raw.close();
        } else {
          expect(await reopened.select(reopened.cashSessions).get(), isEmpty);
          expect(
            await reopened
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE name='retained_marker'",
                )
                .get(),
            isEmpty,
          );
          await reopened.close();
        }
      },
    );
  }
}
