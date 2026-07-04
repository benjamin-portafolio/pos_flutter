import 'package:get_it/get_it.dart';

import '../../application/commands/espacio_command_service.dart';
import '../../application/commands/local_command_context.dart';
import '../../application/sync/event_processor.dart';
import '../../application/sync/handlers/espacio_event_handler.dart';
import '../../application/sync/handlers/espacio_event_registry.dart';
import '../../application/sync/local_event_store.dart';
import '../../application/sync/pending_event_revalidator.dart';
import '../../application/sync/remote_event_applier.dart';
import '../../application/sync/sync_availability_monitor.dart';
import '../../application/sync/sync_endpoint_config.dart';
import '../../application/sync/sync_health_service.dart';
import '../../application/sync/sync_orchestrator.dart';
import '../../application/sync/sync_preflight_service.dart';
import '../../application/sync/sync_pull_service.dart';
import '../../application/sync/sync_push_service.dart';
import '../../application/sync/sync_socket_listener.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/drift/drift_local_event_store.dart';

void registerApplicationDependencies(
  GetIt getIt, {
  required String deviceId,
  required String? storedSyncBaseUrl,
}) {
  getIt.registerSingleton<LocalCommandContext>(
    LocalCommandContext(deviceId: deviceId, userId: 'user_active'),
  );
  getIt.registerSingleton<SyncEndpointConfig>(
    SyncEndpointConfig(initialBaseUrl: _validSyncBaseUrl(storedSyncBaseUrl)),
  );

  getIt.registerLazySingleton<SyncHealthService>(
    () => SyncHealthService(endpointConfig: getIt<SyncEndpointConfig>()),
  );
  getIt.registerLazySingleton<EspacioEventHandler>(
    () => EspacioEventHandler(getIt<EspacioDao>()),
  );
  getIt.registerLazySingleton<EventProcessor>(
    () => EventProcessor(
      handlers: espacioEventHandlers(getIt<EspacioEventHandler>()),
    ),
  );
  getIt.registerLazySingleton<RemoteEventApplier>(
    () => RemoteEventApplier(
      db: getIt<AppDatabase>(),
      eventProcessor: getIt<EventProcessor>(),
    ),
  );
  getIt.registerLazySingleton<PendingEventRevalidator>(
    () => PendingEventRevalidator(
      eventDao: getIt<EventDao>(),
      espacioDao: getIt<EspacioDao>(),
    ),
  );
  getIt.registerLazySingleton<LocalEventStore>(
    () => DriftLocalEventStore(
      db: getIt<AppDatabase>(),
      eventDao: getIt<EventDao>(),
      eventRefDao: getIt<EventRefDao>(),
      eventProcessor: getIt<EventProcessor>(),
    ),
  );
  getIt.registerLazySingleton<SyncPushService>(
    () => SyncPushService(
      eventDao: getIt<EventDao>(),
      eventRefDao: getIt<EventRefDao>(),
      syncCheckpointDao: getIt<SyncCheckpointDao>(),
      endpointConfig: getIt<SyncEndpointConfig>(),
    ),
  );
  getIt.registerLazySingleton<SyncPullService>(
    () => SyncPullService(
      syncCheckpointDao: getIt<SyncCheckpointDao>(),
      remoteEventApplier: getIt<RemoteEventApplier>(),
      endpointConfig: getIt<SyncEndpointConfig>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<SyncPreflightService>(
    () => SyncPreflightService(
      eventDao: getIt<EventDao>(),
      eventRefDao: getIt<EventRefDao>(),
      syncCheckpointDao: getIt<SyncCheckpointDao>(),
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
      syncCheckpointDao: getIt<SyncCheckpointDao>(),
    ),
  );
  getIt.registerLazySingleton<SyncOrchestrator>(
    () => SyncOrchestrator(
      healthService: getIt<SyncHealthService>(),
      preflightService: getIt<SyncPreflightService>(),
      pullService: getIt<SyncPullService>(),
      pushService: getIt<SyncPushService>(),
      socketListener: getIt<SyncSocketListener>(),
    ),
  );
  getIt.registerLazySingleton<SyncAvailabilityMonitor>(
    () => SyncAvailabilityMonitor(
      eventDao: getIt<EventDao>(),
      healthService: getIt<SyncHealthService>(),
      orchestrator: getIt<SyncOrchestrator>(),
    ),
  );

  getIt.registerLazySingleton<EspacioCommandService>(
    () => EspacioCommandService(
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
