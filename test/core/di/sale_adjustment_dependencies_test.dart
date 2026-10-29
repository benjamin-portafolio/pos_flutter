import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/anular_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/prepare_sale_adjustment.dart';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/sale_reconciliation_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/payloads/venta_anulada_payload.dart';
import 'package:pos_flutter/application/sync/projections/cash_projection_store.dart';
import 'package:pos_flutter/application/sync/sync_capability_store.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/config/app_config_file_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import '../../support/sale_adjustment_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in AppMode.values) {
    test(
      'public DI mode=$mode: durable effects, compatibility, refs and no promotion',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'pos-adjustments-di-',
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
        addTearDown(() async {
          await getIt<AppConfigController>().dispose();
          await getIt<AppDatabase>().close();
          await getIt.reset();
          messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
          await dir.delete(recursive: true);
        });
        var network = 0;
        await HttpOverrides.runZoned(
          () async {
            final config = AppConfig.initial.copyWith(
              mode: mode,
              cashEnabled: false,
              setupCompleted: true,
              backupProvider: BackupProvider.none,
            );
            await AppConfigFileStore().saveConfig(config);
            await setupDependencyInjection();
            final db = getIt<AppDatabase>();
            final seed = SaleAdjustmentHarness(db, dir);
            addTearDown(seed.config.dispose);
            final fixture = adjustmentFixtures().firstWhere(
              (f) => f['name'] == 'cash_disabled_no_drawer',
            );
            await seed.seed(fixture);
            final commands = getIt<SaleAdjustmentCommandService>();
            expect(commands.isolatedSyncHarness, false);
            expect(
              getIt<SaleReconciliationCommandService>().isolatedSyncHarness,
              false,
            );
            if (mode == AppMode.serverSync) {
              await expectLater(commands.ensureAvailable(), throwsStateError);
              expect(await db.select(db.saleAdjustmentIntents).get(), isEmpty);
              await getIt<SyncCapabilityStore>().write(
                getIt<SyncEndpointConfig>().baseUrl,
                ['sale_adjustments_v1', 'sale_reconciliations_v1'],
              );
            } else {
              await startConfiguredRuntimeServices(config);
              await commands.ensureAvailable(refresh: true);
            }
            final p =
                await PrepareSaleAdjustment(
                  commands,
                  getIt<CashProjectionStore>(),
                )(
                  saleId: object(fixture['payload'])['sale_id'] as String,
                  expectedRevision: 0,
                  voidSale: true,
                  reason: 'Validación pública de configuración',
                  action: 'refund_completed',
                );
            final command = AnularVentaCommand(
              payload: VentaAnuladaPayload.fromJson(p.toJson()),
              userId: commands.context.userId,
              deviceId: commands.context.deviceId,
            );
            await commands.anular(command);
            await commands.anular(command);
            final event = (await db.select(db.events).get()).singleWhere(
              (e) => e.eventId == p.eventId,
            );
            expect(
              event.deliveryStatus,
              mode == AppMode.standalone ? 'not_required' : 'pending',
            );
            expect((await db.select(db.saleAdjustments).get()).length, 1);
            final refs = await db.eventRefDao.obtenerReferenciasPorEventos([
              p.eventId,
            ]);
            expect(refs.isEmpty, mode == AppMode.standalone);
            if (mode == AppMode.standalone) {
              await stopConfiguredRuntimeServices(config);
              getIt<AppConfigController>().update(
                config.copyWith(mode: AppMode.serverSync),
              );
              expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
              expect(await db.select(db.eventRefs).get(), isEmpty);
              expect(
                (await db.eventDao.obtenerEventoPorId(
                  p.eventId,
                ))!.deliveryStatus,
                'not_required',
              );
            }
            expect(network, 0);
          },
          createHttpClient: (_) {
            network++;
            throw StateError('Network forbidden');
          },
        );
      },
    );
  }
}
