import 'package:get_it/get_it.dart';

import '../../application/commands/espacio_command_service.dart';
import '../../application/commands/local_command_context.dart';
import '../../application/sync/event_processor.dart';
import '../../application/sync/handlers/espacio_event_handler.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/repositories/espacio_repository_impl.dart';
import '../../domain/repositories/espacio_repository.dart';

final getIt = GetIt.instance;

void setupDependencyInjection() {
  final database = AppDatabase();
  getIt.registerSingleton<AppDatabase>(database);
  getIt.registerSingleton<LocalCommandContext>(
    const LocalCommandContext(deviceId: 'device_mobile', userId: 'user_active'),
  );

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

  getIt.registerLazySingleton<EspacioCommandService>(
    () => EspacioCommandService(
      db: getIt<AppDatabase>(),
      eventDao: getIt<EventDao>(),
      eventRefDao: getIt<EventRefDao>(),
      eventProcessor: getIt<EventProcessor>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
}
