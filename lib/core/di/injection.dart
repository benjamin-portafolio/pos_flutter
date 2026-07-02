import 'package:get_it/get_it.dart';

import '../../application/commands/espacio_command_service.dart';
import '../../application/commands/local_command_context.dart';
import '../../application/identity/device_identity_provider.dart';
import '../../application/sync/event_processor.dart';
import '../../application/sync/handlers/espacio_event_handler.dart';
import '../../application/sync/handlers/espacio_event_registry.dart';
import '../../application/sync/local_event_store.dart';
import '../../application/sync/sync_availability_monitor.dart';
import '../../application/sync/sync_endpoint_config.dart';
import '../../application/sync/sync_health_service.dart';
import '../../application/sync/sync_orchestrator.dart';
import '../../application/sync/sync_pull_service.dart';
import '../../application/sync/sync_push_service.dart';
import '../../application/sync/sync_socket_listener.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/drift/drift_local_event_store.dart';
import '../../data/local/identity/device_identity_file_store.dart';
import '../../data/repositories/espacio_repository_impl.dart';
import '../../domain/repositories/espacio_repository.dart';

final getIt = GetIt.instance;

Future<void> setupDependencyInjection() async {
  final database = AppDatabase();
  final deviceIdentityProvider = DeviceIdentityFileStore();
  final deviceId = await deviceIdentityProvider.getDeviceId();

  getIt.registerSingleton<AppDatabase>(database);
  getIt.registerSingleton<DeviceIdentityProvider>(deviceIdentityProvider);
  getIt.registerSingleton<LocalCommandContext>(
    LocalCommandContext(deviceId: deviceId, userId: 'user_active'),
  );
  getIt.registerSingleton<SyncEndpointConfig>(SyncEndpointConfig());

  getIt.registerLazySingleton<EspacioDao>(
    () => EspacioDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<EventDao>(() => EventDao(getIt<AppDatabase>()));
  getIt.registerLazySingleton<EventRefDao>(
    () => EventRefDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<SyncCheckpointDao>(
    () => SyncCheckpointDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<SyncHealthService>(
    () => SyncHealthService(endpointConfig: getIt<SyncEndpointConfig>()),
  );

  getIt.registerLazySingleton<EspacioRepository>(
    () => EspacioRepositoryImpl(espacioDao: getIt<EspacioDao>()),
  );

  getIt.registerLazySingleton<EspacioEventHandler>(
    () => EspacioEventHandler(getIt<EspacioDao>()),
  );
  getIt.registerLazySingleton<EventProcessor>(
    () => EventProcessor(
      handlers: espacioEventHandlers(getIt<EspacioEventHandler>()),
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
      db: getIt<AppDatabase>(),
      syncCheckpointDao: getIt<SyncCheckpointDao>(),
      eventProcessor: getIt<EventProcessor>(),
      endpointConfig: getIt<SyncEndpointConfig>(),
      commandContext: getIt<LocalCommandContext>(),
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
