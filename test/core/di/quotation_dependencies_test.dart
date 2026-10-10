import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/cotizacion_command_service.dart';
import 'package:pos_flutter/application/commands/cotizaciones/guardar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/backup/backup_scheduler.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/projections/quotation_projection_store.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/config/app_config_file_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/repositories/quotation_repository.dart';
import '../../support/quotation_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_quotation_di_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() async {
    await getIt.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });
  for (final mode in AppMode.values) {
    test(
      'P23/P24: runtime inicia servicios solo del modo ${mode.name}',
      () async {
        final backup = _RecordingBackupScheduler();
        final sync = _RecordingSyncMonitor();
        var syncResolved = false;
        getIt.registerSingleton<BackupScheduler>(backup);
        getIt.registerLazySingleton<SyncAvailabilityMonitor>(() {
          syncResolved = true;
          return sync;
        });
        final config = AppConfig.initial.copyWith(
          mode: mode,
          setupCompleted: true,
        );
        await startConfiguredRuntimeServices(config);
        expect(syncResolved, mode == AppMode.serverSync);
        expect(sync.starts, mode == AppMode.serverSync ? 1 : 0);
        expect(backup.starts, mode == AppMode.standalone ? 1 : 0);
        await stopConfiguredRuntimeServices(config);
        expect(sync.stops, mode == AppMode.serverSync ? 1 : 0);
        expect(backup.stops, mode == AppMode.standalone ? 1 : 0);
      },
    );
    test(
      'DI completa resuelve guardar/recuperar/handlers/repositorio en ${mode.name}',
      () async {
        await AppConfigFileStore().saveConfig(
          AppConfig.initial.copyWith(mode: mode),
        );
        await setupDependencyInjection();
        final db = getIt<AppDatabase>();
        final harness = QuotationHarness(database: db, mode: mode);
        try {
          await harness.seed();
          expect(
            getIt<QuotationProjectionStore>(),
            same(getIt<QuotationDao>()),
          );
          await getIt<VentaBorradorCommandService>().agregar(
            const AgregarProductoBorradorCommand(
              variantId: QuotationHarness.directId,
            ),
          );
          final context = getIt<LocalCommandContext>();
          final draft = (await db.saleDao.findDraft(
            context.userId,
            context.deviceId,
          ))!;
          final result = await getIt<CotizacionCommandService>().guardar(
            GuardarCotizacionCommand(
              saleId: draft.id,
              expectedDraftEventId: draft.lastEventId!,
            ),
          );
          final document = (await getIt<QuotationRepository>().findById(
            result.quotationId,
          ))!;
          expect(document.deviceId, context.deviceId);
          expect(document.userId, context.userId);
          expect(
            (await getIt<QuotationRepository>().estimate(document)).totalMinor,
            3500,
          );
          expect(
            (await db.eventDao.obtenerEventoPorId(
              result.eventId,
            ))!.deliveryStatus,
            'not_required',
          );
          await getIt<VentaBorradorCommandService>().limpiar(
            LimpiarVentaBorradorCommand(saleId: draft.id),
          );
          final recovery = await getIt<CotizacionCommandService>().recuperar(
            RecuperarCotizacionCommand(
              quotationId: result.quotationId,
              expectedQuotationEventId: result.eventId,
            ),
          );
          expect((await db.saleDao.findById(recovery.saleId))!.version, 1);
          expect(
            (await db.quotationDao.findById(result.quotationId))!.currentSaleId,
            recovery.saleId,
          );
          expect(
            (await db.eventDao.obtenerEventoPorId(
              recovery.eventId!,
            ))!.deliveryStatus,
            'not_required',
          );
          expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
          expect(
            (await db.select(db.eventRefs).get()).isEmpty,
            mode == AppMode.standalone,
          );
        } finally {
          await harness.dispose();
          getIt<AppConfigController>().dispose();
        }
      },
    );
  }
}

class _RecordingBackupScheduler implements BackupScheduler {
  int starts = 0, stops = 0;
  @override
  void start() => starts++;
  @override
  void stop() => stops++;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected backup call: $invocation');
}

class _RecordingSyncMonitor implements SyncAvailabilityMonitor {
  int starts = 0, stops = 0;
  @override
  void start() => starts++;
  @override
  Future<void> stop() async => stops++;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected sync call: $invocation');
}
