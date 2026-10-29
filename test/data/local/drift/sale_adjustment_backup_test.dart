import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_service.dart';
import 'package:pos_flutter/application/sync/handlers/sale_adjustment_event_handler.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_sale_adjustment_store.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import '../../../support/sale_adjustment_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final incident in [false, true]) {
    test(
      'S18 snapshot/restore real conserva ajustes, refs, intención y cursor; incidencia=$incident',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'pos-adjustment-restore-',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => temp.path,
            );
        final h = await SaleAdjustmentHarness.create();
        h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
        final fixture = adjustmentFixtures().first;
        await h.seed(fixture);
        final handler = SaleAdjustmentEventHandler(
          store: h.store,
          cash: h.cashStore,
          config: h.config,
          isolatedSyncHarness: true,
        );
        final command = SaleAdjustmentCommandService(
          store: h.store,
          events: h.events(handler.apply),
          config: h.config,
          context: h.context,
          isolatedSyncHarness: true,
        );
        final p = object(fixture['payload']);
        await h.execute(p, commands: command);
        final id = p['event_id'] as String;
        if (incident) {
          await h.db.eventDao.actualizarEstadoSincronizacion(
            id,
            'conflict',
            rejectionReason: 'Ganador remoto',
          );
          await h.store.preserveIncident(id, 'Ganador remoto');
        }
        await h.db.syncCheckpointDao.actualizarLastFullPullServerSequence(41);
        final state = await h.store.readDeliveryState();
        final refs = await h.db.eventRefDao.obtenerReferenciasPorEventos([id]);
        final snapshot = await DriftDatabaseSnapshotService(
          db: h.db,
          stateReader: DriftDatabaseStateReader(db: h.db),
        ).createSnapshot();
        AppDatabase? restored;
        try {
          await DriftDatabaseRestoreService(
            db: h.db,
          ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
          restored = AppDatabase();
          final store = DriftSaleAdjustmentStore(restored);
          expect((await store.readDeliveryState()).inventory, state.inventory);
          expect(await store.hasIncident(p['sale_id'] as String), incident);
          expect(
            (await store.recoverIntention(
              p['operation_id'] as String,
            ))!.eventId,
            id,
          );
          expect(
            (await restored.eventDao.obtenerEventoPorId(id))!.deliveryStatus,
            incident ? 'conflict' : 'pending',
          );
          expect(
            await restored.eventRefDao.obtenerReferenciasPorEventos([id]),
            hasLength(refs.length),
          );
          expect(
            await restored.syncCheckpointDao
                .obtenerLastFullPullServerSequence(),
            41,
          );
        } finally {
          await restored?.close();
          await h.config.dispose();
          await h.directory.delete(recursive: true);
          await snapshot.file.parent.delete(recursive: true);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                null,
              );
          await temp.delete(recursive: true);
        }
      },
    );
  }
}
