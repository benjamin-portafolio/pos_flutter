import '../../application/printing/ticket_print_service.dart';
import '../../application/printing/printer_settings_controller.dart';
import 'package:get_it/get_it.dart';

import '../../application/backup/backup_scheduler.dart';
import '../../application/config/app_config.dart';
import '../../application/sync/sync_availability_monitor.dart';
import 'android_backup_background_work.dart';
import 'application_dependencies.dart';
import 'data_dependencies.dart';

final getIt = GetIt.instance;

class DependencyBootstrap {
  const DependencyBootstrap({required this.appConfig});

  final AppConfig appConfig;
}

Future<DependencyBootstrap> setupDependencyInjection() async {
  final bootstrap = await registerDataDependencies(getIt);
  registerApplicationDependencies(
    getIt,
    deviceId: bootstrap.deviceId,
    appConfig: bootstrap.appConfig,
    storedSyncBaseUrl: bootstrap.storedSyncBaseUrl,
    requireWifiForServerDetection: bootstrap.requireWifiForServerDetection,
  );
  await getIt<PrinterSettingsController>().load();
  return DependencyBootstrap(appConfig: bootstrap.appConfig);
}

Future<void> startConfiguredRuntimeServices(AppConfig config) async {
  if (!config.setupCompleted) return;

  if (config.isServerSync) {
    getIt<SyncAvailabilityMonitor>().start();
  } else if (config.usesGoogleDriveBackup) {
    getIt<BackupScheduler>().start();
    await scheduleAndroidBackupBackgroundWork();
  }
}

Future<void> stopConfiguredRuntimeServices(AppConfig config) async {
  if (!config.setupCompleted) return;

  if (config.isServerSync && getIt.isRegistered<SyncAvailabilityMonitor>()) {
    await getIt<SyncAvailabilityMonitor>().stop();
  } else if (config.usesGoogleDriveBackup &&
      getIt.isRegistered<BackupScheduler>()) {
    getIt<BackupScheduler>().stop();
    await cancelAndroidBackupBackgroundWork();
  }
}

Future<DependencyBootstrap> restartDependencyInjection({
  required AppConfig previousConfig,
}) async {
  await stopConfiguredRuntimeServices(previousConfig);
  // reset(dispose: false) cannot terminate native work. Drain printing first;
  // any failed close stops the reset, preserving ownership of the old gateway.
  if (getIt.isRegistered<TicketPrintService>()) {
    await getIt<TicketPrintService>().dispose();
  }
  if (getIt.isRegistered<PrinterSettingsController>()) {
    await getIt<PrinterSettingsController>().dispose();
  }
  await getIt.reset(dispose: false);

  final bootstrap = await setupDependencyInjection();
  await startConfiguredRuntimeServices(bootstrap.appConfig);
  return bootstrap;
}
