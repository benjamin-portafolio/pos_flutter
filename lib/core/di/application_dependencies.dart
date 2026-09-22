import '../../application/commands/creditos/credito_command_service.dart';
import '../../application/sync/handlers/abono_cliente_event_handler.dart';
import '../../application/sync/payloads/abono_cliente_registrado_payload.dart';
import '../../application/sync/projections/customer_credit_store.dart';
import '../../data/local/drift/drift_customer_credit_store.dart';
import '../../data/repositories/customer_account_repository_impl.dart';
import '../../domain/repositories/customer_account_repository.dart';
import '../../application/commands/clientes/cliente_command_service.dart';
import '../../application/sync/handlers/cliente_event_handler.dart';
import '../../application/sync/payloads/cliente_creado_payload.dart';
import '../../application/sync/projections/cliente_projection_store.dart';
import '../../domain/repositories/confirmed_sale_repository.dart';
import '../../data/repositories/confirmed_sale_repository_impl.dart';
import '../../application/commands/ventas/venta_command_service.dart';
import '../../application/sync/projections/confirmed_sale_store.dart';
import '../../application/sync/handlers/venta_confirmada_event_handler.dart';
import '../../application/sync/payloads/venta_confirmada_payload.dart';
import '../../data/local/drift/drift_confirmed_sale_store.dart';
import 'package:get_it/get_it.dart';

import '../../application/backup/backup_scheduler.dart';
import '../../application/backup/backup_service.dart';
import '../../application/backup/backup_store.dart';
import '../../application/commands/categorias/categoria_command_service.dart';
import '../../application/commands/espacios/espacio_command_service.dart';
import '../../application/commands/inventario/inventory_command_service.dart';
import '../../application/commands/local_command_context.dart';
import '../../application/commands/articulos/producto_command_service.dart';
import '../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../application/config/app_config.dart';
import '../../application/config/app_config_controller.dart';
import '../../application/config/app_config_store.dart';
import '../../application/sync/categoria_conflict_projection_restorer.dart';
import '../../application/sync/categoria_eliminada_conflict_projection_restorer.dart';
import '../../application/sync/categoria_movida_conflict_projection_restorer.dart';
import '../../application/sync/device_wifi_connectivity.dart';
import '../../application/sync/event_processor.dart';
import '../../application/sync/handlers/categoria_event_handler.dart';
import '../../application/sync/handlers/categoria_event_registry.dart';
import '../../application/sync/handlers/espacio_event_handler.dart';
import '../../application/sync/handlers/espacio_event_registry.dart';
import '../../application/sync/handlers/inventory_event_handler.dart';
import '../../application/sync/handlers/inventory_event_registry.dart';
import '../../application/sync/handlers/producto_event_handler.dart';
import '../../application/sync/handlers/producto_event_registry.dart';
import '../../application/sync/handlers/venta_borrador_event_handler.dart';
import '../../application/sync/handlers/venta_borrador_limpiada_event_handler.dart';
import '../../application/sync/local_event_store.dart';
import '../../application/sync/payloads/producto_agregado_borrador_payload.dart';
import '../../application/sync/payloads/venta_borrador_limpiada_payload.dart';
import '../../application/sync/pending_event_revalidator.dart';
import '../../application/sync/projections/categoria_projection_store.dart';
import '../../application/sync/projections/espacio_projection_store.dart';
import '../../application/sync/projections/inventory_projection_store.dart';
import '../../application/sync/projections/producto_projection_store.dart';
import '../../application/sync/projections/sale_draft_projection_store.dart';
import '../../application/sync/remote_event_applier.dart';
import '../../application/sync/remote_event_preparer.dart';
import '../../application/sync/server_echo_acknowledger.dart';
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
import '../../application/sync/synced_event_history.dart';
import '../../application/sync/synced_event_store.dart';
import '../../data/local/drift/app_database.dart';
import '../../data/local/drift/drift_local_event_store.dart';
import '../../data/repositories/sale_draft_repository_impl.dart';
import '../../domain/repositories/sale_draft_repository.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';

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
  getIt.registerLazySingleton<ClienteEventHandler>(
    () => ClienteEventHandler(getIt<ClienteProjectionStore>()),
  );
  getIt.registerLazySingleton<ClienteCommandService>(
    () => ClienteCommandService(
      eventStore: getIt<LocalEventStore>(),
      commandContext: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<EspacioEventHandler>(
    () => EspacioEventHandler(getIt<EspacioProjectionStore>()),
  );
  getIt.registerLazySingleton<CategoriaEventHandler>(
    () => CategoriaEventHandler(
      getIt<CategoriaProjectionStore>(),
      getIt<ProductoProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<ProductoEventHandler>(
    () => ProductoEventHandler(
      getIt<ProductoProjectionStore>(),
      inventoryProjectionStore: getIt<InventoryProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<InventoryEventHandler>(
    () => InventoryEventHandler(getIt<InventoryProjectionStore>()),
  );
  getIt.registerLazySingleton<SaleDraftProjectionStore>(
    () => getIt<AppDatabase>().saleDao,
  );
  getIt.registerLazySingleton<SaleDraftRepository>(
    () => SaleDraftRepositoryImpl(
      saleDao: getIt<AppDatabase>().saleDao,
      userId: getIt<LocalCommandContext>().userId,
      deviceId: getIt<LocalCommandContext>().deviceId,
    ),
  );
  getIt.registerLazySingleton<VentaBorradorLimpiadaEventHandler>(
    () => VentaBorradorLimpiadaEventHandler(getIt<SaleDraftProjectionStore>()),
  );
  getIt.registerLazySingleton<VentaBorradorEventHandler>(
    () => VentaBorradorEventHandler(getIt<SaleDraftProjectionStore>()),
  );
  getIt.registerLazySingleton<VentaBorradorCommandService>(
    () => VentaBorradorCommandService(
      store: getIt<SaleDraftProjectionStore>(),
      products: getIt<ProductoProjectionStore>(),
      units: getIt<UnidadInventarioRepository>(),
      events: getIt<LocalEventStore>(),
      context: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<CustomerCreditStore>(
    () => DriftCustomerCreditStore(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<CustomerAccountRepository>(
    () => CustomerAccountRepositoryImpl(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<CreditoCommandService>(
    () => CreditoCommandService(
      store: getIt<CustomerCreditStore>(),
      clientes: getIt<ClienteProjectionStore>(),
      events: getIt<LocalEventStore>(),
      context: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<AbonoClienteEventHandler>(
    () => AbonoClienteEventHandler(getIt<CustomerCreditStore>()),
  );
  getIt.registerLazySingleton<ConfirmedSaleStore>(
    () => DriftConfirmedSaleStore(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ConfirmedSaleRepository>(
    () => ConfirmedSaleRepositoryImpl(getIt<ConfirmedSaleStore>()),
  );
  getIt.registerLazySingleton<VentaConfirmadaEventHandler>(
    () => VentaConfirmadaEventHandler(getIt<ConfirmedSaleStore>()),
  );
  getIt.registerLazySingleton<VentaCommandService>(
    () => VentaCommandService(
      clientes: getIt<ClienteProjectionStore>(),
      drafts: getIt<SaleDraftProjectionStore>(),
      products: getIt<ProductoProjectionStore>(),
      inventory: getIt<InventoryProjectionStore>(),
      events: getIt<LocalEventStore>(),
      context: getIt<LocalCommandContext>(),
    ),
  );
  getIt.registerLazySingleton<EventProcessor>(
    () => EventProcessor(
      handlers: {
        AbonoClienteRegistradoPayload.eventType:
            getIt<AbonoClienteEventHandler>().apply,
        ClienteCreadoPayload.eventType: getIt<ClienteEventHandler>().apply,
        VentaConfirmadaPayload.eventType:
            getIt<VentaConfirmadaEventHandler>().apply,
        VentaBorradorLimpiadaPayload.eventType:
            getIt<VentaBorradorLimpiadaEventHandler>().apply,
        ProductoAgregadoBorradorPayload.eventType:
            getIt<VentaBorradorEventHandler>().apply,
        ...espacioEventHandlers(getIt<EspacioEventHandler>()),
        ...categoriaEventHandlers(getIt<CategoriaEventHandler>()),
        ...productoEventHandlers(getIt<ProductoEventHandler>()),
        ...inventoryEventHandlers(getIt<InventoryEventHandler>()),
      },
    ),
  );
  getIt.registerLazySingleton<ServerEchoAcknowledger>(
    () => ServerEchoAcknowledger(
      customerCreditStore: getIt<CustomerCreditStore>(),
      clienteProjectionStore: getIt<ClienteProjectionStore>(),
      confirmedSaleStore: getIt<ConfirmedSaleStore>(),
      categoriaProjectionStore: getIt<CategoriaProjectionStore>(),
      productoProjectionStore: getIt<ProductoProjectionStore>(),
      inventoryProjectionStore: getIt<InventoryProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<CategoriaConflictProjectionRestorer>(
    () =>
        CategoriaConflictProjectionRestorer(getIt<CategoriaProjectionStore>()),
  );
  getIt.registerLazySingleton<CategoriaMovidaConflictProjectionRestorer>(
    () => CategoriaMovidaConflictProjectionRestorer(
      getIt<CategoriaProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<CategoriaEliminadaConflictProjectionRestorer>(
    () => CategoriaEliminadaConflictProjectionRestorer(
      getIt<CategoriaProjectionStore>(),
      getIt<ProductoProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<RemoteEventPreparer>(
    () => RemoteEventPreparer(
      syncPersistence: getIt<SyncPersistence>(),
      categoriaEliminadaConflictProjectionRestorer:
          getIt<CategoriaEliminadaConflictProjectionRestorer>(),
      conflictProjectionCleaner: getIt<SyncConflictProjectionCleaner>(),
    ),
  );
  getIt.registerLazySingleton<RemoteEventApplier>(
    () => RemoteEventApplier(
      eventStore: getIt<SyncedEventStore>(),
      eventProcessor: getIt<EventProcessor>(),
      serverEchoAcknowledger: getIt<ServerEchoAcknowledger>(),
      remoteEventPreparer: getIt<RemoteEventPreparer>(),
    ),
  );
  getIt.registerLazySingleton<PendingEventRevalidator>(
    () => PendingEventRevalidator(
      clienteProjectionStore: getIt<ClienteProjectionStore>(),
      syncPersistence: getIt<SyncPersistence>(),
      syncedEventHistory: getIt<SyncedEventHistory>(),
      espacioProjectionStore: getIt<EspacioProjectionStore>(),
      categoriaProjectionStore: getIt<CategoriaProjectionStore>(),
      productoProjectionStore: getIt<ProductoProjectionStore>(),
      inventoryProjectionStore: getIt<InventoryProjectionStore>(),
      categoriaConflictProjectionRestorer:
          getIt<CategoriaConflictProjectionRestorer>(),
      categoriaMovidaConflictProjectionRestorer:
          getIt<CategoriaMovidaConflictProjectionRestorer>(),
      categoriaEliminadaConflictProjectionRestorer:
          getIt<CategoriaEliminadaConflictProjectionRestorer>(),
    ),
  );
  getIt.registerLazySingleton<SyncConflictProjectionCleaner>(
    () => SyncConflictProjectionCleaner(
      clienteProjectionStore: getIt<ClienteProjectionStore>(),
      espacioProjectionStore: getIt<EspacioProjectionStore>(),
      categoriaProjectionStore: getIt<CategoriaProjectionStore>(),
      productoProjectionStore: getIt<ProductoProjectionStore>(),
      inventoryProjectionStore: getIt<InventoryProjectionStore>(),
      categoriaConflictProjectionRestorer:
          getIt<CategoriaConflictProjectionRestorer>(),
      categoriaMovidaConflictProjectionRestorer:
          getIt<CategoriaMovidaConflictProjectionRestorer>(),
      categoriaEliminadaConflictProjectionRestorer:
          getIt<CategoriaEliminadaConflictProjectionRestorer>(),
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
      categoriaProjectionStore: getIt<CategoriaProjectionStore>(),
      productoProjectionStore: getIt<ProductoProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<ProductoCommandService>(
    () => ProductoCommandService(
      productoProjectionStore: getIt<ProductoProjectionStore>(),
      eventStore: getIt<LocalEventStore>(),
      commandContext: getIt<LocalCommandContext>(),
      categoriaProjectionStore: getIt<CategoriaProjectionStore>(),
      syncedEventHistory: getIt<SyncedEventHistory>(),
      unidadInventarioRepository: getIt<UnidadInventarioRepository>(),
      inventoryProjectionStore: getIt<InventoryProjectionStore>(),
    ),
  );
  getIt.registerLazySingleton<InventoryCommandService>(
    () => InventoryCommandService(
      eventStore: getIt<LocalEventStore>(),
      commandContext: getIt<LocalCommandContext>(),
      inventoryProjectionStore: getIt<InventoryProjectionStore>(),
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
