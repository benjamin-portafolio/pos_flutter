import 'package:get_it/get_it.dart';

import '../../application/commands/espacio_command_service.dart';
import '../../application/commands/local_command_context.dart';
import '../../application/sync/event_processor.dart';
import '../../application/sync/handlers/espacio_event_handler.dart';
import '../../application/sync/local_event_store.dart';
import '../../application/sync/sync_endpoint_config.dart';
import '../../application/sync/sync_orchestrator.dart';
import '../../application/sync/sync_push_service.dart';
import '../../application/sync/sync_socket_listener.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/drift/drift_local_event_store.dart';
import '../../data/repositories/espacio_repository_impl.dart';
import '../../domain/repositories/espacio_repository.dart';

final getIt = GetIt.instance;

void setupDependencyInjection() {
  final database = AppDatabase();
  getIt.registerSingleton<AppDatabase>(database);
  getIt.registerSingleton<LocalCommandContext>(
    const LocalCommandContext(deviceId: 'device_mobile', userId: 'user_active'),
  );
  getIt.registerSingleton<SyncEndpointConfig>(SyncEndpointConfig());

  getIt.registerLazySingleton<EspacioDao>(
    () => EspacioDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<EventDao>(() => EventDao(getIt<AppDatabase>()));
  getIt.registerLazySingleton<EventRefDao>(
    () => EventRefDao(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<EspacioRepository>(
    () => EspacioRepositoryImpl(espacioDao: getIt<EspacioDao>()),
  );

  getIt.registerLazySingleton<EspacioEventHandler>(
    () => EspacioEventHandler(getIt<EspacioDao>()),
  );
  getIt.registerLazySingleton<EventProcessor>(
    () => EventProcessor(espacioEventHandler: getIt<EspacioEventHandler>()),
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
      endpointConfig: getIt<SyncEndpointConfig>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<SyncSocketListener>(
    () => SyncSocketListener(
      endpointConfig: getIt<SyncEndpointConfig>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<SyncOrchestrator>(
    () => SyncOrchestrator(
      eventDao: getIt<EventDao>(),
      pushService: getIt<SyncPushService>(),
      socketListener: getIt<SyncSocketListener>(),
    ),
  );

  getIt.registerLazySingleton<EspacioCommandService>(
    () => EspacioCommandService(
      eventStore: getIt<LocalEventStore>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
}
