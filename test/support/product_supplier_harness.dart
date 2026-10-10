import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_descartado_payload.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/proveedores/crear_proveedor_command.dart';
import 'package:pos_flutter/application/commands/proveedores/proveedor_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';

import 'variant_tracking_harness.dart';

/// Reutiliza el flujo de producto/inventario existente con SQLite aislado.
class ProductSupplierHarness {
  ProductSupplierHarness({
    AppDatabase? database,
    AppMode mode = AppMode.standalone,
    LocalCommandContext context = const LocalCommandContext(
      deviceId: 'supplier-device',
      userId: 'supplier-user',
    ),
  }) : tracking = VariantTrackingHarness(
         database: database,
         mode: mode,
         context: context,
       );

  final VariantTrackingHarness tracking;
  AppDatabase get db => tracking.db;
  bool failAfterProductApply = false;
  final appends = <LocalEventAppend>[];

  late final local = DriftLocalEventStore(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    appConfigController: tracking.config,
    eventProcessor: EventProcessor(
      handlers: {
        for (final type in [
          ProveedorCreadoPayload.eventType,
          ProveedorActualizadoPayload.eventType,
          RecursoInventarioCreadoPayload.eventType,
          RecursoInventarioDescartadoPayload.eventType,
          ProductoCreadoPayload.eventType,
          ProductoActualizadoPayload.eventType,
        ])
          type: (event) async {
            await tracking.processor.apply(event);
            if (failAfterProductApply &&
                event.aggregateType == ProductoCreadoPayload.aggregateType) {
              throw StateError(
                'fallo inyectado después de proyectar producto e hijos',
              );
            }
          },
      },
    ),
  );
  late final events = _RecordingEvents(local, appends);
  late final supplierCommands = ProveedorCommandService(
    eventStore: events,
    projectionStore: tracking.suppliers,
    commandContext: tracking.context,
    config: tracking.config,
    history: tracking.history,
  );
  late final commands = ProductoCommandService(
    eventStore: events,
    commandContext: tracking.context,
    categoriaProjectionStore: tracking.categories,
    syncedEventHistory: tracking.history,
    unidadInventarioRepository: UnidadInventarioRepositoryImpl(
      unitDao: db.unitDao,
    ),
    inventoryProjectionStore: tracking.inventory,
    productoProjectionStore: tracking.products,
    proveedorProjectionStore: tracking.suppliers,
    variantInventoryMemoryStore: tracking.memory,
    variantInventoryTrackingStore: tracking.tracking,
  );
  late final repository = ProductoRepositoryImpl(productoDao: db.productoDao);

  Future<String> supplier(String name) async {
    await supplierCommands.crearProveedor(CrearProveedorCommand(nombre: name));
    return (await ProveedorRepositoryImpl(
      db.proveedorDao,
    ).watchProveedores().first).singleWhere((s) => s.nombre == name).id;
  }

  Future<void> dispose() async {
    await tracking.config.dispose();
    await db.close();
  }
}

class _RecordingEvents
    implements
        LocalEventStore,
        LocalTransactionalEventStore,
        LocalAtomicEventBatchStore {
  _RecordingEvents(this.delegate, this.appends);
  final DriftLocalEventStore delegate;
  final List<LocalEventAppend> appends;
  @override
  bool get isStandalone => delegate.isStandalone;
  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      delegate.runInTransaction(action);
  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) {
    appends.add(LocalEventAppend(event: event, refs: refs));
    return delegate.appendAndApply(event, refs: refs);
  }

  @override
  Future<void> appendAndApplyBatchAtomically(List<LocalEventAppend> entries) {
    appends.addAll(entries);
    return delegate.appendAndApplyBatchAtomically(entries);
  }
}
