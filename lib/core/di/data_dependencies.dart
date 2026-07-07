import 'package:get_it/get_it.dart';

import '../../application/identity/device_identity_provider.dart';
import '../../application/sync/device_wifi_connectivity.dart';
import '../../application/sync/projections/espacio_projection_store.dart';
import '../../application/sync/sync_detection_settings_store.dart';
import '../../application/sync/sync_endpoint_store.dart';
import '../../application/sync/sync_persistence.dart';
import '../../application/sync/synced_event_store.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/drift/drift_espacio_projection_store.dart';
import '../../data/local/drift/drift_sync_persistence.dart';
import '../../data/local/drift/drift_synced_event_store.dart';
import '../../data/local/identity/device_identity_file_store.dart';
import '../../data/local/sync/connectivity_plus_wifi_connectivity.dart';
import '../../data/local/sync/sync_detection_settings_file_store.dart';
import '../../data/local/sync/sync_endpoint_file_store.dart';
import '../../data/repositories/espacio_repository_impl.dart';
import '../../domain/repositories/espacio_repository.dart';

class DataDependencyBootstrap {
  const DataDependencyBootstrap({
    required this.deviceId,
    required this.storedSyncBaseUrl,
    required this.requireWifiForServerDetection,
  });

  final String deviceId;
  final String? storedSyncBaseUrl;
  final bool requireWifiForServerDetection;
}

Future<DataDependencyBootstrap> registerDataDependencies(GetIt getIt) async {
  final database = AppDatabase();
  final deviceIdentityProvider = DeviceIdentityFileStore();
  final syncEndpointStore = SyncEndpointFileStore();
  final syncDetectionSettingsStore = SyncDetectionSettingsFileStore();
  final deviceId = await deviceIdentityProvider.getDeviceId();
  final storedSyncBaseUrl = await syncEndpointStore.readBaseUrl();
  final requireWifiForServerDetection = await syncDetectionSettingsStore
      .readRequireWifiForServerDetection();

  getIt.registerSingleton<AppDatabase>(database);
  getIt.registerSingleton<DeviceIdentityProvider>(deviceIdentityProvider);
  getIt.registerSingleton<SyncEndpointStore>(syncEndpointStore);
  getIt.registerSingleton<SyncDetectionSettingsStore>(
    syncDetectionSettingsStore,
  );
  getIt.registerLazySingleton<DeviceWifiConnectivity>(
    () => ConnectivityPlusWifiConnectivity(),
  );

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
  getIt.registerLazySingleton<SyncPersistence>(
    () => DriftSyncPersistence(
      eventDao: getIt<EventDao>(),
      eventRefDao: getIt<EventRefDao>(),
      syncCheckpointDao: getIt<SyncCheckpointDao>(),
    ),
  );
  getIt.registerLazySingleton<SyncedEventStore>(
    () => DriftSyncedEventStore(db: getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<EspacioProjectionStore>(
    () => DriftEspacioProjectionStore(espacioDao: getIt<EspacioDao>()),
  );

  getIt.registerLazySingleton<EspacioRepository>(
    () => EspacioRepositoryImpl(espacioDao: getIt<EspacioDao>()),
  );

  return DataDependencyBootstrap(
    deviceId: deviceId,
    storedSyncBaseUrl: storedSyncBaseUrl,
    requireWifiForServerDetection: requireWifiForServerDetection,
  );
}
