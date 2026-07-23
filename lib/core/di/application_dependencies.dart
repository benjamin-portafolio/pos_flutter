import 'package:get_it/get_it.dart';

import '../../application/backup/backup_scheduler.dart';
import '../../application/backup/backup_service.dart';
import '../../application/backup/backup_store.dart';
import '../../application/config/app_config.dart';
import '../../application/config/app_config_controller.dart';
import '../../application/config/app_config_store.dart';
import '../../application/commands/categoria_command_service.dart';
import '../../application/commands/espacio_command_service.dart';
import '../../application/commands/local_command_context.dart';
import '../../application/sync/device_wifi_connectivity.dart';
import '../../application/sync/event_processor.dart';
import '../../application/sync/handlers/categoria_event_handler.dart';
import '../../application/sync/handlers/categoria_event_registry.dart';
import '../../application/sync/handlers/espacio_event_handler.dart';
import '../../application/sync/handlers/espacio_event_registry.dart';
import '../../application/sync/local_event_store.dart';
import '../../application/sync/pending_event_revalidator.dart';
import '../../application/sync/projections/categoria_projection_store.dart';
import '../../application/sync/projections/espacio_projection_store.dart';
import '../../application/sync/remote_event_applier.dart';
import '../../application/sync/sync_availability_monitor.dart';
import '../../application/sync/sync_conflict_projection_cleaner.dart';
import '../../application/sync/sync_conflict_report_service.dart';
import '../../application/sync/sync_endpoint_config.dart';
import '../../application/sync/sync_health_service.dart';
import '../../application/sync/sync_orchestrator.dart';
import '../../application/sync/sync_persistence.dart';
import '../../application/sync/sync_preflight_service.dart';
import '../../application/sync/sync_pull_service.dart';
import '../../application/sync/sync_push_service.dart';
import '../../application/sync/sync_server_detection_config.dart';
import '../../application/sync/sync_socket_listener.dart';
import '../../application/sync/synced_event_store.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/drift/drift_local_event_store.dart';

void registerApplicationDependencies(
  GetIt getIt, {
  required String deviceId,
  required AppConfig appConfig,
  required String? storedSyncBaseUrl,
  required bool requireWifiForServerDetection,
}) {
  getIt.registerSingleton<AppConfigController>(AppConfigController(appConfig));
  getIt.registerSingleton<LocalCommandContext>(
    LocalCommandContext(deviceId: deviceId, userId: appConfig.userId),
  );
  getIt.registerSingleton<SyncEndpointConfig>(
    SyncEndpointConfig(initialBaseUrl: _validSyncBaseUrl(storedSyncBaseUrl)),
  );
  getIt.registerSingleton<SyncServerDetectionConfig>(
    SyncServerDetectionConfig(
      requireWifiForServerDetection: requireWifiForServerDetection,
    ),
  );

  getIt.registerLazySingleton<SyncHealthService>(
    () => SyncHealthService(endpointConfig: getIt<SyncEndpointConfig>()),
  );
  getIt.registerLazySingleton<EspacioEventHandler>(
    () => EspacioEventHandler(getIt<EspacioProjectionStore>()),
  );
  getIt.registerLazySingleton<CategoriaEventHandler>(
    () => CategoriaEventHandler(getIt<CategoriaProjectionStore>()),
  );
  getIt.registerLazySingleton<EventProcessor>(
    () => EventProcessor(
      handlers: {
        ...espacioEventHandlers(getIt<EspacioEventHandler>()),
        ...categoriaEventHandlers(getIt<CategoriaEventHandler>()),
      },
    ),
  );
  getIt.registerLazySingleton<RemoteEventApplier>(
    () => RemoteEventApplier(
      eventStore: getIt<SyncedEventStore>(),
      eventProcessor: getIt<EventProcessor>(),
    ),
  );
  getIt.registerLazySingleton<PendingEventRevalidator>(
    () => PendingEventRevalidator(
      syncPersistence: getIt<SyncPersistence>(),
      espacioProjectionStore: getIt<EspacioProjectionStore>(),
      categoriaProjectionStore: getIt<CategoriaProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<SyncConflictProjectionCleaner>(
    () => SyncConflictProjectionCleaner(
      espacioProjectionStore: getIt<EspacioProjectionStore>(),
      categoriaProjectionStore: getIt<CategoriaProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<LocalEventStore>(
    () => DriftLocalEventStore(
      db: getIt<AppDatabase>(),
      eventDao: getIt<EventDao>(),
      eventRefDao: getIt<EventRefDao>(),
      eventProcessor: getIt<EventProcessor>(),
      appConfigController: getIt<AppConfigController>(),
    ),
  );
  getIt.registerLazySingleton<SyncPushService>(
    () => SyncPushService(
      syncPersistence: getIt<SyncPersistence>(),
      endpointConfig: getIt<SyncEndpointConfig>(),
      conflictProjectionCleaner: getIt<SyncConflictProjectionCleaner>(),
    ),
  );
  getIt.registerLazySingleton<SyncConflictReportService>(
    () => SyncConflictReportService(
      syncPersistence: getIt<SyncPersistence>(),
      endpointConfig: getIt<SyncEndpointConfig>(),
      conflictProjectionCleaner: getIt<SyncConflictProjectionCleaner>(),
    ),
  );
  getIt.registerLazySingleton<SyncPullService>(
    () => SyncPullService(
      syncPersistence: getIt<SyncPersistence>(),
      remoteEventApplier: getIt<RemoteEventApplier>(),
      endpointConfig: getIt<SyncEndpointConfig>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<SyncPreflightService>(
    () => SyncPreflightService(
      syncPersistence: getIt<SyncPersistence>(),
      endpointConfig: getIt<SyncEndpointConfig>(),
      commandContext: getIt<LocalCommandContext>(),
      remoteEventApplier: getIt<RemoteEventApplier>(),
      pendingEventRevalidator: getIt<PendingEventRevalidator>(),
    ),
  );
  getIt.registerLazySingleton<SyncSocketListener>(
    () => SyncSocketListener(
      endpointConfig: getIt<SyncEndpointConfig>(),
      commandContext: getIt<LocalCommandContext>(),
      syncPersistence: getIt<SyncPersistence>(),
    ),
  );
  getIt.registerLazySingleton<SyncOrchestrator>(
    () => SyncOrchestrator(
      healthService: getIt<SyncHealthService>(),
      preflightService: getIt<SyncPreflightService>(),
      conflictReportService: getIt<SyncConflictReportService>(),
      pullService: getIt<SyncPullService>(),
      pushService: getIt<SyncPushService>(),
      socketListener: getIt<SyncSocketListener>(),
    ),
  );
  getIt.registerLazySingleton<SyncAvailabilityMonitor>(
    () => SyncAvailabilityMonitor(
      syncPersistence: getIt<SyncPersistence>(),
      healthService: getIt<SyncHealthService>(),
      orchestrator: getIt<SyncOrchestrator>(),
      serverDetectionConfig: getIt<SyncServerDetectionConfig>(),
      wifiConnectivity: getIt<DeviceWifiConnectivity>(),
    ),
  );
  getIt.registerLazySingleton<BackupService>(
    () => BackupService(
      deviceId: deviceId,
      appConfigController: getIt<AppConfigController>(),
      appConfigStore: getIt<AppConfigStore>(),
      backupStore: getIt<BackupStore>(),
      stateReader: getIt<DatabaseStateReader>(),
      snapshotService: getIt<DatabaseSnapshotService>(),
      restoreService: getIt<DatabaseRestoreService>(),
    ),
  );
  getIt.registerLazySingleton<BackupScheduler>(
    () => BackupScheduler(
      appConfigController: getIt<AppConfigController>(),
      backupService: getIt<BackupService>(),
    ),
  );

  getIt.registerLazySingleton<EspacioCommandService>(
    () => EspacioCommandService(
      eventStore: getIt<LocalEventStore>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<CategoriaCommandService>(
    () => CategoriaCommandService(
      eventStore: getIt<LocalEventStore>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
}

String _validSyncBaseUrl(String? storedBaseUrl) {
  if (storedBaseUrl == null) return SyncEndpointConfig.defaultBaseUrl;

  try {
    return SyncEndpointConfig.normalizeBaseUrl(storedBaseUrl);
  } on FormatException {
    return SyncEndpointConfig.defaultBaseUrl;
  }
}
