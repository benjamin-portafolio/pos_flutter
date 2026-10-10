import 'package:pos_flutter/application/sync/handlers/proveedor_creado_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/proveedor_actualizado_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_actualizado_payload.dart';
import 'package:pos_flutter/data/local/drift/drift_proveedor_projection_store.dart';
import 'package:pos_flutter/application/sync/sync_preflight_service.dart';
import 'package:pos_flutter/application/sync/pending_event_revalidator.dart';
import 'package:pos_flutter/application/sync/remote_event_preparer.dart';
import 'package:pos_flutter/application/sync/categoria_eliminada_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/inventory_resource_resolver.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/articulos/producto_inventory_update_result.dart';
import 'package:pos_flutter/application/commands/inventario/inventory_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/application/sync/handlers/venta_confirmada_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_discard_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/inventory_discard_policy.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_variant_inventory_memory_store.dart';
import 'package:pos_flutter/data/local/drift/drift_variant_inventory_tracking_store.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

/// Commands, event store and projections used in production, against isolated SQLite.
class VariantTrackingHarness {
  VariantTrackingHarness({
    AppMode mode = AppMode.standalone,
    AppDatabase? database,
    this.context = const LocalCommandContext(
      deviceId: 'phase3-device',
      userId: 'phase3-user',
    ),
  }) : db = database ?? AppDatabase.forTesting(NativeDatabase.memory()) {
    config = AppConfigController(
      AppConfig.initial.copyWith(mode: mode, setupCompleted: true),
    );
    inventory = DriftInventoryProjectionStore(
      inventoryDao: InventoryDao(db),
      unitDao: UnitDao(db),
    );
    products = DriftProductoProjectionStore(productoDao: ProductoDao(db));
    memory = DriftVariantInventoryMemoryStore(
      dao: VariantInventoryMemoryDao(db),
    );
    tracking = DriftVariantInventoryTrackingStore(
      inventoryDao: InventoryDao(db),
      productoDao: ProductoDao(db),
    );
    categories = DriftCategoriaProjectionStore(categoriaDao: CategoriaDao(db));
    history = DriftSyncPersistence(
      db: db,
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      syncCheckpointDao: SyncCheckpointDao(db),
    );
    processor = EventProcessor(
      handlers: {
        ProveedorCreadoPayload.eventType: ProveedorCreadoEventHandler(
          suppliers,
        ).apply,
        ProveedorActualizadoPayload.eventType: ProveedorActualizadoEventHandler(
          suppliers,
        ).apply,
        ...productoEventHandlers(
          ProductoEventHandler(
            products,
            proveedorProjectionStore: suppliers,
            variantInventoryMemoryStore: memory,
            inventoryProjectionStore: inventory,
          ),
        ),
        ...inventoryEventHandlers(
          InventoryEventHandler(
            inventory,
            trackingStore: tracking,
            discardHandler: InventoryDiscardEventHandler(
              inventoryStore: inventory,
              productStore: products,
              trackingStore: tracking,
              history: history,
              policy: InventoryDiscardPolicy(
                trackingStore: tracking,
                memoryStore: memory,
              ),
              isStandalone: () => config.config.mode == AppMode.standalone,
            ),
          ),
        ),
        VentaConfirmadaPayload.eventType: VentaConfirmadaEventHandler(
          DriftConfirmedSaleStore(db),
        ).apply,
        ProductoAgregadoBorradorPayload.eventType: VentaBorradorEventHandler(
          SaleDao(db),
        ).apply,
      },
    );
    events = DriftLocalEventStore(
      db: db,
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      eventProcessor: processor,
      appConfigController: config,
    );
    final units = UnidadInventarioRepositoryImpl(unitDao: UnitDao(db));
    commands = ProductoCommandService(
      eventStore: events,
      proveedorProjectionStore: suppliers,
      commandContext: context,
      categoriaProjectionStore: categories,
      syncedEventHistory: history,
      unidadInventarioRepository: units,
      inventoryProjectionStore: inventory,
      productoProjectionStore: products,
      variantInventoryMemoryStore: memory,
      variantInventoryTrackingStore: tracking,
    );
    inventoryCommands = InventoryCommandService(
      eventStore: events,
      commandContext: context,
      inventoryProjectionStore: inventory,
    );
    drafts = VentaBorradorCommandService(
      store: SaleDao(db),
      products: products,
      units: units,
      events: events,
      context: context,
    );
    sales = VentaCommandService(
      drafts: SaleDao(db),
      products: products,
      inventory: inventory,
      events: events,
      context: context,
    );
    resolver = InventoryResourceResolver(
      memoryStore: memory,
      trackingStore: tracking,
      inventoryStore: inventory,
    );
    cleaner = SyncConflictProjectionCleaner(
      proveedorProjectionStore: suppliers,
      espacioProjectionStore: DriftEspacioProjectionStore(
        espacioDao: EspacioDao(db),
      ),
      categoriaProjectionStore: categories,
      categoriaConflictProjectionRestorer: CategoriaConflictProjectionRestorer(
        categories,
      ),
      categoriaMovidaConflictProjectionRestorer:
          CategoriaMovidaConflictProjectionRestorer(categories),
      productoProjectionStore: products,
      inventoryProjectionStore: inventory,
    );
    remote = RemoteEventApplier(
      remoteEventPreparer: RemoteEventPreparer(
        syncPersistence: history,
        conflictProjectionCleaner: cleaner,
        categoriaEliminadaConflictProjectionRestorer:
            CategoriaEliminadaConflictProjectionRestorer(categories, products),
      ),
      eventStore: DriftSyncedEventStore(db: db),
      eventProcessor: processor,
      serverEchoAcknowledger: ServerEchoAcknowledger(
        proveedorProjectionStore: suppliers,
        confirmedSaleStore: DriftConfirmedSaleStore(db),
        categoriaProjectionStore: categories,
        productoProjectionStore: products,
        inventoryProjectionStore: inventory,
        variantInventoryMemoryStore: memory,
      ),
    );
  }
  final LocalCommandContext context;
  final AppDatabase db;
  late final suppliers = DriftProveedorProjectionStore(db.proveedorDao);
  late final AppConfigController config;
  late final DriftInventoryProjectionStore inventory;
  late final DriftProductoProjectionStore products;
  late final DriftVariantInventoryMemoryStore memory;
  late final DriftVariantInventoryTrackingStore tracking;
  late final DriftCategoriaProjectionStore categories;
  late final DriftSyncPersistence history;
  late final EventProcessor processor;
  late final DriftLocalEventStore events;
  late final ProductoCommandService commands;
  late final InventoryCommandService inventoryCommands;
  late final VentaBorradorCommandService drafts;
  late final VentaCommandService sales;
  late final InventoryResourceResolver resolver;
  late final RemoteEventApplier remote;
  late final SyncConflictProjectionCleaner cleaner;

  Future<({String productId, String variantId, String? resourceId})> create({
    bool tracked = true,
    String? initial,
    String name = 'Artículo',
    SaleConfiguration sale = const UnitSaleConfiguration(),
    String unit = InventoryUnitIds.piece,
  }) async {
    await commands.crearArticulo(
      CrearArticuloCommand.conVariantes(
        nombre: name,
        saleConfiguration: sale,
        variantes: [
          CrearArticuloVarianteCommand(
            nombre: null,
            precioVenta: '10',
            costoEstandar: null,
            inventoryUnitId: tracked ? unit : null,
            initialStockQuantity: initial,
          ),
        ],
      ),
    );
    final product = (await db.select(db.products).get()).last;
    final variant = (await products.snapshot(product.id)).variantes.single;
    return (
      productId: product.id,
      variantId: variant.id,
      resourceId: variant.inventoryItemId,
    );
  }

  Future<ProductoInventoryUpdateResult> save(
    String productId,
    String variantId, {
    bool tracked = false,
    String? selected,
    String? initial,
    List<CrearArticuloRecipeComponentCommand> recipe = const [],
    String name = 'Artículo',
    String unit = InventoryUnitIds.piece,
  }) async {
    final p = (await products.findProductById(productId))!;
    return commands.actualizarArticulo(
      productId: productId,
      baseEventId: p.lastEventId!,
      variantIds: [variantId],
      command: CrearArticuloCommand.conVariantes(
        nombre: name,
        saleConfiguration: p.saleConfiguration,
        variantes: [
          CrearArticuloVarianteCommand(
            nombre: null,
            precioVenta: '10',
            costoEstandar: null,
            inventoryUnitId: tracked ? unit : null,
            existingInventoryItemId: selected,
            initialStockQuantity: initial,
            recipeComponents: recipe,
          ),
        ],
      ),
    );
  }

  SyncPushService push(String url) => SyncPushService(
    syncPersistence: history,
    endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
    conflictProjectionCleaner: cleaner,
  );
  SyncPreflightService preflight(String url) => SyncPreflightService(
    syncPersistence: history,
    endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
    commandContext: context,
    remoteEventApplier: remote,
    pendingEventRevalidator: PendingEventRevalidator(
      proveedorProjectionStore: suppliers,
      syncPersistence: history,
      syncedEventHistory: history,
      espacioProjectionStore: DriftEspacioProjectionStore(
        espacioDao: EspacioDao(db),
      ),
      categoriaProjectionStore: categories,
      productoProjectionStore: products,
      inventoryProjectionStore: inventory,
      categoriaConflictProjectionRestorer: CategoriaConflictProjectionRestorer(
        categories,
      ),
      categoriaMovidaConflictProjectionRestorer:
          CategoriaMovidaConflictProjectionRestorer(categories),
      categoriaEliminadaConflictProjectionRestorer:
          CategoriaEliminadaConflictProjectionRestorer(categories, products),
    ),
  );

  SyncPullService pull(String url) => SyncPullService(
    syncPersistence: history,
    remoteEventApplier: remote,
    endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
    commandContext: context,
  );

  Future<List<SyncEvent>> storedEvents() async {
    final rows = await (db.select(
      db.events,
    )..orderBy([(e) => OrderingTerm.asc(e.localSequence)])).get();
    return [for (final row in rows) (await history.eventById(row.eventId))!];
  }
}
