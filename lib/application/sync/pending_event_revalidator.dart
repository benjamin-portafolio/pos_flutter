import 'payloads/cliente_creado_payload.dart';
import 'projections/cliente_projection_store.dart';
import 'revalidation/cliente_pending_event_validator.dart';
import 'payloads/venta_confirmada_payload.dart';
import 'revalidation/sale_pending_event_validator.dart';
import 'categoria_conflict_projection_restorer.dart';
import 'categoria_eliminada_conflict_projection_restorer.dart';
import 'categoria_movida_conflict_projection_restorer.dart';
import 'models/pending_revalidation_report.dart';
import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/categoria_eliminada_payload.dart';
import 'payloads/categoria_movida_payload.dart';
import 'payloads/espacio_creado_payload.dart';
import 'payloads/movimiento_inventario_registrado_payload.dart';
import 'payloads/producto_actualizado_payload.dart';
import 'payloads/producto_creado_payload.dart';
import 'payloads/recurso_inventario_actualizado_payload.dart';
import 'payloads/recurso_inventario_creado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/espacio_projection_store.dart';
import 'projections/inventory_projection_store.dart';
import 'projections/producto_projection_store.dart';
import 'revalidation/categoria_pending_event_validator.dart';
import 'revalidation/espacio_pending_event_validator.dart';
import 'revalidation/inventory_pending_event_validator.dart';
import 'revalidation/pending_conflict.dart';
import 'revalidation/pending_event_dependency_resolver.dart';
import 'revalidation/pending_event_validator.dart';
import 'revalidation/producto_pending_event_validator.dart';
import 'sync_persistence.dart';
import 'synced_event_history.dart';

class PendingEventRevalidator {
  PendingEventRevalidator({
    ClienteProjectionStore? clienteProjectionStore,
    required SyncPersistence syncPersistence,
    required SyncedEventHistory syncedEventHistory,
    required EspacioProjectionStore espacioProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
    ProductoProjectionStore? productoProjectionStore,
    InventoryProjectionStore? inventoryProjectionStore,
    required CategoriaConflictProjectionRestorer
    categoriaConflictProjectionRestorer,
    required CategoriaMovidaConflictProjectionRestorer
    categoriaMovidaConflictProjectionRestorer,
    CategoriaEliminadaConflictProjectionRestorer?
    categoriaEliminadaConflictProjectionRestorer,
  }) : _syncPersistence = syncPersistence {
    final dependencies = PendingEventDependencyResolver(syncedEventHistory);
    final space = EspacioPendingEventValidator(
      espacioProjectionStore: espacioProjectionStore,
    );
    final category = CategoriaPendingEventValidator(
      categoriaProjectionStore: categoriaProjectionStore,
      productoProjectionStore: productoProjectionStore,
      syncedEventHistory: syncedEventHistory,
      dependencies: dependencies,
      categoriaConflictProjectionRestorer: categoriaConflictProjectionRestorer,
      categoriaMovidaConflictProjectionRestorer:
          categoriaMovidaConflictProjectionRestorer,
      categoriaEliminadaConflictProjectionRestorer:
          categoriaEliminadaConflictProjectionRestorer,
    );
    final product = ProductoPendingEventValidator(
      productoProjectionStore: productoProjectionStore,
      categoriaProjectionStore: categoriaProjectionStore,
      inventoryProjectionStore: inventoryProjectionStore,
      syncPersistence: syncPersistence,
      syncedEventHistory: syncedEventHistory,
      dependencies: dependencies,
    );
    final inventory = InventoryPendingEventValidator(
      inventoryProjectionStore: inventoryProjectionStore,
      syncedEventHistory: syncedEventHistory,
      dependencies: dependencies,
    );
    _validators = {
      if (clienteProjectionStore != null)
        ClienteCreadoPayload.eventType: ClientePendingEventValidator(
          clienteProjectionStore,
        ),
      VentaConfirmadaPayload.eventType: SalePendingEventValidator(
        syncedEventHistory,
      ),
      EspacioCreadoPayload.eventType: space,
      CategoriaCreadaPayload.eventType: category,
      CategoriaActualizadaPayload.eventType: category,
      CategoriaMovidaPayload.eventType: category,
      CategoriaEliminadaPayload.eventType: category,
      ProductoActualizadoPayload.eventType: product,
      ProductoCreadoPayload.eventType: product,
      RecursoInventarioCreadoPayload.eventType: inventory,
      RecursoInventarioActualizadoPayload.eventType: inventory,
      MovimientoInventarioRegistradoPayload.eventType: inventory,
    };
  }

  final SyncPersistence _syncPersistence;
  late final Map<String, PendingEventValidator> _validators;

  Future<PendingRevalidationReport> revalidatePendingEvents() async {
    final events = await _syncPersistence.pendingEvents();
    final detected = <({SyncEvent event, PendingConflict conflict})>[];
    final conflictedEventIds = <String>{};

    for (final event in events) {
      final validator = _validators[event.eventType];
      if (validator == null) continue;
      final conflict = await validator.validate(event, conflictedEventIds);

      if (conflict == null) continue;

      detected.add((event: event, conflict: conflict));
      conflictedEventIds.add(event.eventId);
    }

    await _syncPersistence.runInTransaction(() async {
      for (final entry in detected) {
        await _syncPersistence.updateEventSyncStatus(
          entry.event.eventId,
          'conflict',
          rejectionReason: entry.conflict.reason,
        );
      }
      for (final entry in detected.reversed) {
        await _validators[entry.event.eventType]!.restore(
          entry.event,
          entry.conflict,
        );
      }
    });

    return PendingRevalidationReport(
      checked: events.length,
      conflicts: detected.length,
    );
  }
}
