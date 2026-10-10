import '../../application/printing/printer_gateway.dart';
import '../../application/printing/ticket_encoder.dart';
import '../../data/printing/esc_pos_ticket_encoder.dart';
import '../../application/printing/printer_settings_store.dart';
import '../../data/local/printing/printer_settings_file_store.dart';
import '../../data/printing/android_bluetooth_printer_gateway.dart';
import '../../application/sync/projections/proveedor_projection_store.dart';
import '../../data/local/drift/drift_proveedor_projection_store.dart';
import '../../data/repositories/proveedor_repository_impl.dart';
import '../../domain/repositories/proveedor_repository.dart';
import '../../domain/repositories/cash_repository.dart';
import '../../data/repositories/cash_repository_impl.dart';
import '../../application/sync/projections/cash_projection_store.dart';
import '../../data/local/drift/drift_cash_projection_store.dart';
import '../../application/sync/projections/account_balance_baseline_projection_store.dart';
import '../../data/local/drift/drift_account_balance_baseline_projection_store.dart';
import '../../data/repositories/account_balance_baseline_repository_impl.dart';
import '../../domain/repositories/account_balance_baseline_repository.dart';
import '../../application/sync/projections/cliente_projection_store.dart';
import '../../data/local/drift/drift_cliente_projection_store.dart';
import '../../data/repositories/cliente_repository_impl.dart';
import '../../data/repositories/cliente_resumen_repository_impl.dart';
import '../../domain/repositories/cliente_repository.dart';
import '../../domain/repositories/cliente_resumen_repository.dart';
import 'package:get_it/get_it.dart';

import '../../application/config/app_config.dart';
import '../../application/config/app_config_store.dart';
import '../../application/export/articulo_catalog_export_service.dart';
import '../../application/import/articulo_catalog_import_service.dart';
import '../../application/identity/device_identity_provider.dart';
import '../../application/backup/backup_service.dart';
import '../../application/backup/backup_store.dart';
import '../../application/sync/device_wifi_connectivity.dart';
import '../../application/sync/projections/categoria_projection_store.dart';
import '../../application/sync/projections/espacio_projection_store.dart';
import '../../application/sync/projections/financial_category_projection_store.dart';
import '../../application/sync/projections/financial_entry_projection_store.dart';
import '../../application/sync/projections/inventory_projection_store.dart';
import '../../application/sync/projections/producto_projection_store.dart';
import '../../application/sync/sync_detection_settings_store.dart';
import '../../application/sync/sync_endpoint_store.dart';
import '../../application/sync/sync_persistence.dart';
import '../../application/sync/synced_event_history.dart';
import '../../application/sync/synced_event_store.dart';
import '../../data/local/config/app_config_file_store.dart';
import '../../data/local/export/drift_articulo_catalog_export_service.dart';
import '../../data/local/import/articulo_import_csv.dart';
import '../../data/google_drive/google_drive_auth_service.dart';
import '../../data/google_drive/google_drive_backup_store.dart';
import '../../data/local/backup/database_restore_service.dart';
import '../../data/local/backup/database_snapshot_service.dart';
import '../../data/local/backup/database_state_reader.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/drift/drift_categoria_projection_store.dart';
import '../../data/local/drift/drift_espacio_projection_store.dart';
import '../../data/local/drift/drift_financial_category_projection_store.dart';
import '../../data/local/drift/drift_financial_entry_projection_store.dart';
import '../../data/local/drift/drift_inventory_projection_store.dart';
import '../../data/local/drift/drift_producto_projection_store.dart';
import '../../application/sync/projections/variant_inventory_memory_store.dart';
import '../../data/local/drift/drift_variant_inventory_memory_store.dart';
import '../../application/sync/projections/variant_inventory_tracking_store.dart';
import '../../data/local/drift/drift_variant_inventory_tracking_store.dart';
import '../../data/local/drift/drift_sync_persistence.dart';
import '../../data/local/drift/drift_synced_event_store.dart';
import '../../data/local/identity/device_identity_file_store.dart';
import '../../data/local/sync/connectivity_plus_wifi_connectivity.dart';
import '../../data/local/sync/sync_detection_settings_file_store.dart';
import '../../data/local/sync/sync_endpoint_file_store.dart';
import '../../data/repositories/categoria_repository_impl.dart';
import '../../data/repositories/espacio_repository_impl.dart';
import '../../data/repositories/financial_category_repository_impl.dart';
import '../../data/repositories/financial_entry_repository_impl.dart';
import '../../data/repositories/transfer_summary_repository_impl.dart';
import '../../domain/repositories/transfer_summary_repository.dart';
import '../../data/repositories/recurso_inventario_repository_impl.dart';
import '../../data/repositories/unidad_inventario_repository_impl.dart';
import '../../data/repositories/producto_repository_impl.dart';
import '../../domain/repositories/categoria_repository.dart';
import '../../domain/repositories/espacio_repository.dart';
import '../../domain/repositories/financial_category_repository.dart';
import '../../domain/repositories/financial_entry_repository.dart';
import '../../domain/repositories/recurso_inventario_repository.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';
import '../../domain/repositories/producto_repository.dart';
import '../../application/sync/projections/quotation_projection_store.dart';

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
  getIt.registerLazySingleton<TicketEncoder>(() => const EscPosTicketEncoder());
  getIt.registerLazySingleton<PrinterSettingsStore>(
    () => PrinterSettingsFileStore(),
  );
  getIt.registerLazySingleton<PrinterGateway>(
    () => AndroidBluetoothPrinterGateway(),
    dispose: (gateway) => gateway.close(),
  );
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

  getIt.registerLazySingleton<ProveedorDao>(
    () => getIt<AppDatabase>().proveedorDao,
  );
  getIt.registerLazySingleton<ProveedorProjectionStore>(
    () => DriftProveedorProjectionStore(getIt<ProveedorDao>()),
  );
  getIt.registerLazySingleton<ProveedorRepository>(
    () => ProveedorRepositoryImpl(getIt<ProveedorDao>()),
  );
  getIt.registerLazySingleton<ClienteDao>(
    () => getIt<AppDatabase>().clienteDao,
  );
  getIt.registerLazySingleton<ClienteProjectionStore>(
    () => DriftClienteProjectionStore(getIt<ClienteDao>()),
  );
  getIt.registerLazySingleton<ClienteRepository>(
    () => ClienteRepositoryImpl(getIt<ClienteDao>()),
  );
  getIt.registerLazySingleton<ClienteResumenRepository>(
    () => ClienteResumenRepositoryImpl(getIt<AppDatabase>()),
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
  getIt.registerLazySingleton<QuotationDao>(
    () => getIt<AppDatabase>().quotationDao,
  );
  getIt.registerLazySingleton<QuotationProjectionStore>(
    () => getIt<QuotationDao>(),
  );
  getIt.registerLazySingleton<FinancialCategoryDao>(
    () => getIt<AppDatabase>().financialCategoryDao,
  );
  getIt.registerLazySingleton<FinancialEntryDao>(
    () => getIt<AppDatabase>().financialEntryDao,
  );
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
  getIt.registerLazySingleton<VariantInventoryMemoryDao>(
    () => VariantInventoryMemoryDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<VariantInventoryMemoryStore>(
    () => DriftVariantInventoryMemoryStore(
      dao: getIt<VariantInventoryMemoryDao>(),
    ),
  );
  getIt.registerLazySingleton<VariantInventoryTrackingStore>(
    () => DriftVariantInventoryTrackingStore(
      inventoryDao: getIt<InventoryDao>(),
      productoDao: getIt<ProductoDao>(),
    ),
  );
  getIt.registerLazySingleton<CashRepository>(
    () => CashRepositoryImpl(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<CashProjectionStore>(
    () => DriftCashProjectionStore(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<AccountBalanceBaselineProjectionStore>(
    () => DriftAccountBalanceBaselineProjectionStore(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<FinancialCategoryProjectionStore>(
    () => DriftFinancialCategoryProjectionStore(
      db: getIt<AppDatabase>(),
      dao: getIt<FinancialCategoryDao>(),
    ),
  );
  getIt.registerLazySingleton<FinancialEntryProjectionStore>(
    () => DriftFinancialEntryProjectionStore(
      db: getIt<AppDatabase>(),
      dao: getIt<FinancialEntryDao>(),
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
  getIt.registerLazySingleton<FinancialCategoryRepository>(
    () => FinancialCategoryRepositoryImpl(getIt<FinancialCategoryDao>()),
  );
  getIt.registerLazySingleton<FinancialEntryRepository>(
    () => FinancialEntryRepositoryImpl(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<TransferSummaryRepository>(
    () => TransferSummaryRepositoryImpl(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<AccountBalanceBaselineRepository>(
    () => AccountBalanceBaselineRepositoryImpl(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ArticuloCatalogExportService>(
    () => DriftArticuloCatalogExportService(
      productoDao: getIt<ProductoDao>(),
      configStore: getIt<AppConfigStore>(),
    ),
  );
  // El servicio de validación no lee la base: recibe el catálogo ya resuelto
  // desde la pantalla, así que es una implementación pura, sin Drift.
  getIt.registerLazySingleton<ArticuloCatalogImportService>(
    () => const ArticuloImportCsv(),
  );

  return DataDependencyBootstrap(
    deviceId: deviceId,
    appConfig: appConfig,
    storedSyncBaseUrl: storedSyncBaseUrl,
    requireWifiForServerDetection: requireWifiForServerDetection,
  );
}
