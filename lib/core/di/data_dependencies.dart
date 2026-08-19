import 'package:get_it/get_it.dart';

import '../../application/config/app_config.dart';
import '../../application/config/app_config_store.dart';
import '../../application/identity/device_identity_provider.dart';
import '../../application/backup/backup_service.dart';
import '../../application/backup/backup_store.dart';
import '../../application/sync/device_wifi_connectivity.dart';
import '../../application/sync/projections/categoria_projection_store.dart';
import '../../application/sync/projections/espacio_projection_store.dart';
import '../../application/sync/projections/inventory_projection_store.dart';
import '../../application/sync/projections/producto_projection_store.dart';
import '../../application/sync/sync_detection_settings_store.dart';
import '../../application/sync/sync_endpoint_store.dart';
import '../../application/sync/sync_persistence.dart';
import '../../application/sync/synced_event_history.dart';
import '../../application/sync/synced_event_store.dart';
import '../../data/local/config/app_config_file_store.dart';
import '../../data/google_drive/google_drive_auth_service.dart';
import '../../data/google_drive/google_drive_backup_store.dart';
import '../../data/local/backup/database_restore_service.dart';
import '../../data/local/backup/database_snapshot_service.dart';
import '../../data/local/backup/database_state_reader.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/drift/drift_categoria_projection_store.dart';
import '../../data/local/drift/drift_espacio_projection_store.dart';
import '../../data/local/drift/drift_inventory_projection_store.dart';
import '../../data/local/drift/drift_producto_projection_store.dart';
import '../../data/local/drift/drift_sync_persistence.dart';
import '../../data/local/drift/drift_synced_event_store.dart';
import '../../data/local/identity/device_identity_file_store.dart';
import '../../data/local/sync/connectivity_plus_wifi_connectivity.dart';
import '../../data/local/sync/sync_detection_settings_file_store.dart';
import '../../data/local/sync/sync_endpoint_file_store.dart';
import '../../data/repositories/categoria_repository_impl.dart';
import '../../data/repositories/espacio_repository_impl.dart';
import '../../data/repositories/recurso_inventario_repository_impl.dart';
import '../../data/repositories/unidad_inventario_repository_impl.dart';
import '../../data/repositories/producto_repository_impl.dart';
import '../../domain/repositories/categoria_repository.dart';
import '../../domain/repositories/espacio_repository.dart';
import '../../domain/repositories/recurso_inventario_repository.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';
import '../../domain/repositories/producto_repository.dart';

class DataDependencyBootstrap {
  const DataDependencyBootstrap({
    required this.deviceId,
    required this.appConfig,
    required this.storedSyncBaseUrl,
    required this.requireWifiForServerDetection,
  });

  final String deviceId;
  final AppConfig appConfig;
  final String? storedSyncBaseUrl;
  final bool requireWifiForServerDetection;
}

Future<DataDependencyBootstrap> registerDataDependencies(GetIt getIt) async {
  final appConfigStore = AppConfigFileStore();
  final deviceIdentityProvider = DeviceIdentityFileStore();
  final syncEndpointStore = SyncEndpointFileStore();
  final syncDetectionSettingsStore = SyncDetectionSettingsFileStore();
  final appConfig = await appConfigStore.readConfig();
  final deviceId = await deviceIdentityProvider.getDeviceId();
  final storedSyncBaseUrl = await syncEndpointStore.readBaseUrl();
  final requireWifiForServerDetection = await syncDetectionSettingsStore
      .readRequireWifiForServerDetection();

  getIt.registerLazySingleton<AppDatabase>(() => AppDatabase());
  getIt.registerSingleton<AppConfigStore>(appConfigStore);
  getIt.registerSingleton<DeviceIdentityProvider>(deviceIdentityProvider);
  getIt.registerSingleton<SyncEndpointStore>(syncEndpointStore);
  getIt.registerSingleton<SyncDetectionSettingsStore>(
    syncDetectionSettingsStore,
  );
  getIt.registerLazySingleton<DeviceWifiConnectivity>(
    () => ConnectivityPlusWifiConnectivity(),
  );
  getIt.registerLazySingleton<GoogleDriveAuthService>(
    () => GoogleDriveAuthService(),
  );
  getIt.registerLazySingleton<BackupStore>(
    () => GoogleDriveBackupStore(authService: getIt<GoogleDriveAuthService>()),
  );

  getIt.registerLazySingleton<EspacioDao>(
    () => EspacioDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<CategoriaDao>(
    () => CategoriaDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ProductoDao>(
    () => ProductoDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<EventDao>(() => EventDao(getIt<AppDatabase>()));
  getIt.registerLazySingleton<UnitDao>(() => UnitDao(getIt<AppDatabase>()));
  getIt.registerLazySingleton<InventoryDao>(
    () => InventoryDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<EventRefDao>(
    () => EventRefDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<SyncCheckpointDao>(
    () => SyncCheckpointDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<DatabaseStateReader>(
    () => DriftDatabaseStateReader(db: getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<DatabaseSnapshotService>(
    () => DriftDatabaseSnapshotService(
      db: getIt<AppDatabase>(),
      stateReader: getIt<DatabaseStateReader>(),
    ),
  );
  getIt.registerLazySingleton<DatabaseRestoreService>(
    () => DriftDatabaseRestoreService(db: getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<DriftSyncPersistence>(
    () => DriftSyncPersistence(
      db: getIt<AppDatabase>(),
      eventDao: getIt<EventDao>(),
      eventRefDao: getIt<EventRefDao>(),
      syncCheckpointDao: getIt<SyncCheckpointDao>(),
    ),
  );
  getIt.registerLazySingleton<SyncPersistence>(
    () => getIt<DriftSyncPersistence>(),
  );
  getIt.registerLazySingleton<SyncedEventHistory>(
    () => getIt<DriftSyncPersistence>(),
  );
  getIt.registerLazySingleton<SyncedEventStore>(
    () => DriftSyncedEventStore(db: getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<EspacioProjectionStore>(
    () => DriftEspacioProjectionStore(espacioDao: getIt<EspacioDao>()),
  );
  getIt.registerLazySingleton<CategoriaProjectionStore>(
    () => DriftCategoriaProjectionStore(categoriaDao: getIt<CategoriaDao>()),
  );
  getIt.registerLazySingleton<ProductoProjectionStore>(
    () => DriftProductoProjectionStore(productoDao: getIt<ProductoDao>()),
  );
  getIt.registerLazySingleton<InventoryProjectionStore>(
    () => DriftInventoryProjectionStore(
      inventoryDao: getIt<InventoryDao>(),
      unitDao: getIt<UnitDao>(),
    ),
  );

  getIt.registerLazySingleton<EspacioRepository>(
    () => EspacioRepositoryImpl(espacioDao: getIt<EspacioDao>()),
  );
  getIt.registerLazySingleton<CategoriaRepository>(
    () => CategoriaRepositoryImpl(categoriaDao: getIt<CategoriaDao>()),
  );
  getIt.registerLazySingleton<ProductoRepository>(
    () => ProductoRepositoryImpl(productoDao: getIt<ProductoDao>()),
  );
  getIt.registerLazySingleton<UnidadInventarioRepository>(
    () => UnidadInventarioRepositoryImpl(unitDao: getIt<UnitDao>()),
  );
  getIt.registerLazySingleton<RecursoInventarioRepository>(
    () => RecursoInventarioRepositoryImpl(inventoryDao: getIt<InventoryDao>()),
  );

  return DataDependencyBootstrap(
    deviceId: deviceId,
    appConfig: appConfig,
    storedSyncBaseUrl: storedSyncBaseUrl,
    requireWifiForServerDetection: requireWifiForServerDetection,
  );
}
