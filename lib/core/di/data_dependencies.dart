import 'package:get_it/get_it.dart';

import '../../application/identity/device_identity_provider.dart';
import '../../application/sync/sync_endpoint_store.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/identity/device_identity_file_store.dart';
import '../../data/local/sync/sync_endpoint_file_store.dart';
import '../../data/repositories/espacio_repository_impl.dart';
import '../../domain/repositories/espacio_repository.dart';

class DataDependencyBootstrap {
  const DataDependencyBootstrap({
    required this.deviceId,
    required this.storedSyncBaseUrl,
  });

  final String deviceId;
  final String? storedSyncBaseUrl;
}

Future<DataDependencyBootstrap> registerDataDependencies(GetIt getIt) async {
  final database = AppDatabase();
  final deviceIdentityProvider = DeviceIdentityFileStore();
  final syncEndpointStore = SyncEndpointFileStore();
  final deviceId = await deviceIdentityProvider.getDeviceId();
  final storedSyncBaseUrl = await syncEndpointStore.readBaseUrl();

  getIt.registerSingleton<AppDatabase>(database);
  getIt.registerSingleton<DeviceIdentityProvider>(deviceIdentityProvider);
  getIt.registerSingleton<SyncEndpointStore>(syncEndpointStore);

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

  getIt.registerLazySingleton<EspacioRepository>(
    () => EspacioRepositoryImpl(espacioDao: getIt<EspacioDao>()),
  );

  return DataDependencyBootstrap(
    deviceId: deviceId,
    storedSyncBaseUrl: storedSyncBaseUrl,
  );
}
