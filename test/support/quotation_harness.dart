import 'package:pos_flutter/application/commands/caja/caja_command_service.dart';
import 'package:pos_flutter/application/commands/clientes/cliente_command_service.dart';
import 'package:pos_flutter/application/commands/clientes/crear_cliente_command.dart';
import 'package:pos_flutter/application/sync/handlers/cash_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/cliente_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/caja_abierta_payload.dart';
import 'package:pos_flutter/application/sync/payloads/cliente_creado_payload.dart';
import 'package:pos_flutter/data/local/drift/drift_cash_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_cliente_projection_store.dart';
import 'package:pos_flutter/application/sync/handlers/cotizacion_recuperada_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_recuperada_payload.dart';
import 'package:pos_flutter/application/sync/quotation_recovery_validator.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pos_flutter/application/commands/cotizaciones/cotizacion_command_service.dart';
import 'package:pos_flutter/application/commands/cotizaciones/guardar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/cotizacion_guardada_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_actualizado_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_limpiada_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_confirmada_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_guardada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_borrador_limpiada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/repositories/quotation_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

/// SQLite real en memoria o archivo temporal; catálogo directo, receta y medida.
class QuotationHarness {
  QuotationHarness({AppDatabase? database, AppMode mode = AppMode.standalone})
    : db = database ?? AppDatabase.forTesting(NativeDatabase.memory()),
      config = AppConfigController(
        AppConfig.initial.copyWith(mode: mode, cashEnabled: false),
      );

  static const productId = '00000000-0000-4000-8000-000000000001';
  static const directId = '00000000-0000-4000-8000-000000000002';
  static const recipeId = '00000000-0000-4000-8000-000000000003';
  static const measuredId = '00000000-0000-4000-8000-000000000004';
  static const resourceId = '00000000-0000-4000-8000-000000000005';
  static const configId = '00000000-0000-4000-8000-000000000006';
  static const measuredProductId = '00000000-0000-4000-8000-000000000007';
  static const resourceEventId = '00000000-0000-4000-8000-000000000008';

  final AppDatabase db;
  final AppConfigController config;
  final context = const LocalCommandContext(
    userId: 'quotation-user',
    deviceId: 'quotation-tablet',
  );
  bool failAfterSave = false;
  bool failAfterRecovery = false;
  late final validator = QuotationRecoveryValidator(
    products: products,
    units: UnidadInventarioRepositoryImpl(unitDao: db.unitDao),
  );
  late final recoveryHandler = CotizacionRecuperadaEventHandler(
    store: db.quotationDao,
    drafts: db.saleDao,
  );
  late final handler = CotizacionGuardadaEventHandler(
    store: db.quotationDao,
    drafts: db.saleDao,
  );
  late final products = DriftProductoProjectionStore(
    productoDao: db.productoDao,
  );
  late final events = DriftLocalEventStore(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    appConfigController: config,
    eventProcessor: EventProcessor(
      handlers: {
        CajaAbiertaPayload.eventType: CashEventHandler(
          DriftCashProjectionStore(db),
        ).apply,
        ClienteCreadoPayload.eventType: ClienteEventHandler(
          DriftClienteProjectionStore(db.clienteDao),
        ).apply,
        CotizacionRecuperadaPayload.eventType: (event) async {
          await recoveryHandler.apply(event);
          if (failAfterRecovery) throw StateError('fallo después de recuperar');
        },
        CotizacionGuardadaPayload.eventType: (event) async {
          await handler.apply(event);
          if (failAfterSave) throw StateError('fallo después de aplicar');
        },
        ProductoAgregadoBorradorPayload.eventType: VentaBorradorEventHandler(
          db.saleDao,
        ).apply,
        ProductoActualizadoBorradorPayload.eventType:
            VentaBorradorActualizadoEventHandler(db.saleDao).apply,
        VentaBorradorLimpiadaPayload.eventType:
            VentaBorradorLimpiadaEventHandler(db.saleDao).apply,
        VentaConfirmadaPayload.eventType: VentaConfirmadaEventHandler(
          DriftConfirmedSaleStore(db),
          cash: CashEventHandler(DriftCashProjectionStore(db)),
        ).apply,
      },
    ),
  );
  CotizacionCommandService service({LocalCommandContext? owner}) =>
      CotizacionCommandService(
        store: db.quotationDao,
        drafts: db.saleDao,
        validator: validator,
        events: events,
        context: owner ?? context,
      );
  late final drafts = VentaBorradorCommandService(
    store: db.saleDao,
    products: products,
    units: UnidadInventarioRepositoryImpl(unitDao: db.unitDao),
    events: events,
    context: context,
  );
  late final repository = QuotationRepositoryImpl(
    dao: db.quotationDao,
    validator: validator,
    userId: context.userId,
    deviceId: context.deviceId,
  );

  Future<void> seed() async {
    await db
        .into(db.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            id: resourceId,
            name: 'Recurso',
            defaultUnitId: InventoryUnitIds.piece,
            createdEventId: const Value(resourceEventId),
            lastEventId: const Value(resourceEventId),
          ),
        );
    await db
        .into(db.inventoryBalances)
        .insert(
          InventoryBalancesCompanion.insert(
            inventoryItemId: resourceId,
            quantityOnHandAtomic: 1000,
            quantityAvailableAtomic: 1000,
            lastEventId: resourceEventId,
          ),
        );
    for (final measured in [false, true]) {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: measured ? measuredProductId : productId,
              name: measured ? 'Café medido' : 'Pan',
              saleMode: Value(measured ? 'measured' : 'unit'),
              saleUnitId: Value(measured ? InventoryUnitIds.kilogram : null),
              priceReferenceQuantityAtomic: Value(measured ? 1000 : null),
              createdEventId: const Value(configId),
              lastEventId: const Value(configId),
            ),
          );
    }
    for (final id in [directId, recipeId, measuredId]) {
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: id,
              productId: id == measuredId ? measuredProductId : productId,
              name: Value(id == recipeId ? 'Por receta' : 'Original'),
              nameKey: Value(id),
              salePriceMinor: id == measuredId
                  ? 10001
                  : id == recipeId
                  ? 2400
                  : 3500,
              standardCostMinor: const Value(900),
              inventoryItemId: Value(id == directId ? resourceId : null),
              sortOrder: id == recipeId ? 1 : 0,
              createdEventId: const Value(configId),
              lastEventId: const Value(configId),
            ),
          );
    }
    await db
        .into(db.recipeComponents)
        .insert(
          RecipeComponentsCompanion.insert(
            variantId: recipeId,
            inventoryItemId: resourceId,
            quantityAtomic: 3,
          ),
        );
    for (final id in [configId, resourceEventId]) {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              eventId: id,
              aggregateType: 'fixture',
              aggregateId: id,
              eventType: 'fixture',
              userId: context.userId,
              deviceId: context.deviceId,
              createdAtLocal: DateTime.utc(2026),
              payload: '{}',
              deliveryStatus: const Value('not_required'),
            ),
          );
    }
  }

  Future<void> add([String variantId = directId]) => drafts.agregar(
    AgregarProductoBorradorCommand(
      variantId: variantId,
      measuredQuantity: variantId == measuredId ? '0.750' : null,
      expectedUnitId: variantId == measuredId
          ? InventoryUnitIds.kilogram
          : null,
    ),
  );
  Future<GuardarCotizacionCommand> intent() async {
    final sale = (await db.saleDao.findDraft(
      context.userId,
      context.deviceId,
    ))!;
    return GuardarCotizacionCommand(
      saleId: sale.id,
      expectedDraftEventId: sale.lastEventId!,
    );
  }

  late final cash = CajaCommandService(
    store: DriftCashProjectionStore(db),
    events: events,
    context: context,
    config: config,
  );
  Future<String> customer() async {
    await ClienteCommandService(
      clienteProjectionStore: DriftClienteProjectionStore(db.clienteDao),
      eventStore: events,
      commandContext: context,
    ).crearCliente(const CrearClienteCommand(nombre: 'Ana', telefono: '555'));
    return (await db.select(db.clientes).get()).single.id;
  }

  Future<String> confirm({
    String method = 'cash',
    String? clienteId,
    String? saleId,
  }) async {
    final sale = (saleId == null
        ? await db.saleDao.findDraft(context.userId, context.deviceId)
        : await db.saleDao.findById(saleId))!;
    return VentaCommandService(
      cash: cash,
      clientes: DriftClienteProjectionStore(db.clienteDao),
      drafts: db.saleDao,
      products: products,
      inventory: DriftInventoryProjectionStore(
        inventoryDao: db.inventoryDao,
        unitDao: db.unitDao,
      ),
      events: events,
      context: context,
    ).confirmar(
      ConfirmarVentaCommand(
        saleId: sale.id,
        expectedDraftEventId: sale.lastEventId!,
        expectedTotalMinor: sale.totalMinor,
        paymentMethod: method,
        paymentReference: method == 'transfer' ? 'SPEI-123' : null,
        clienteId: clienteId,
      ),
    );
  }

  /// Compara contenido, saldos y proyecciones, no sólo conteos de movimientos.
  Future<Map<String, Object?>> contents({
    Set<String> excluded = const {},
  }) async => {
    for (final table in db.allTables)
      if (!excluded.contains(table.actualTableName))
        table.actualTableName:
            (await db
                    .customSelect(
                      'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                    )
                    .get())
                .map((row) => row.data)
                .toList(),
  };
  Future<void> dispose() async {
    await db.close();
    config.dispose();
  }
}
