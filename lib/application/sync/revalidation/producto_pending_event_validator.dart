import '../models/sync_event.dart';
import '../payloads/producto_actualizado_payload.dart';
import '../payloads/producto_creado_payload.dart';
import '../projections/categoria_projection_store.dart';
import '../projections/inventory_projection_store.dart';
import '../projections/producto_projection_store.dart';
import '../sync_persistence.dart';
import '../synced_event_history.dart';
import 'pending_conflict.dart';
import 'pending_event_dependency_resolver.dart';
import 'pending_event_validator.dart';

class ProductoPendingEventValidator implements PendingEventValidator {
  ProductoPendingEventValidator({
    required ProductoProjectionStore? productoProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
    required InventoryProjectionStore? inventoryProjectionStore,
    required SyncPersistence syncPersistence,
    required SyncedEventHistory syncedEventHistory,
    required PendingEventDependencyResolver dependencies,
  }) : _productoProjectionStore = productoProjectionStore,
       _categoriaProjectionStore = categoriaProjectionStore,
       _inventoryProjectionStore = inventoryProjectionStore,
       _syncPersistence = syncPersistence,
       _syncedEventHistory = syncedEventHistory,
       _dependencies = dependencies;

  final ProductoProjectionStore? _productoProjectionStore;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final InventoryProjectionStore? _inventoryProjectionStore;
  final SyncPersistence _syncPersistence;
  final SyncedEventHistory _syncedEventHistory;
  final PendingEventDependencyResolver _dependencies;

  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    final dependencyConflict = await _dependencyConflict(
      event,
      conflictedEventIds,
    );
    if (dependencyConflict != null) return dependencyConflict;
    return switch (event.eventType) {
      ProductoActualizadoPayload.eventType =>
        await _productoActualizadoConflict(event),
      ProductoCreadoPayload.eventType => await _productoCreadoConflict(event),
      _ => null,
    };
  }

  Future<PendingConflict?> _dependencyConflict(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    if (event.eventType == ProductoActualizadoPayload.eventType) {
      for (final id in ProductoActualizadoPayload.fromJson(
        event.payload,
      ).dependencyEventIds) {
        if (conflictedEventIds.contains(id) ||
            await _dependencies.hasFailed(id)) {
          return const PendingConflict(
            'La actualización depende de un evento en conflicto.',
          );
        }
      }
    }
    if (event.eventType == ProductoCreadoPayload.eventType) {
      final payload = ProductoCreadoPayload.fromJson(event.payload);
      final dependencyEventIds = <String>{
        ...payload.dependenciasInventario
            .map((dependency) => dependency.dependsOnEventId)
            .whereType<String>(),
      };
      final categoryDependencyEventId =
          payload.dependenciaCategoria?.dependsOnEventId;
      if (categoryDependencyEventId != null) {
        dependencyEventIds.add(categoryDependencyEventId);
      }
      for (final dependencyEventId in dependencyEventIds) {
        if (conflictedEventIds.contains(dependencyEventId) ||
            await _dependencies.hasFailed(dependencyEventId)) {
          return const PendingConflict(
            'El artículo depende de una categoría o recurso local en conflicto.',
          );
        }
      }
    }
    return null;
  }

  Future<PendingConflict?> _productoActualizadoConflict(SyncEvent event) async {
    final payload = ProductoActualizadoPayload.fromJson(event.payload);
    final product = await _productoProjectionStore?.findProductById(
      event.aggregateId,
    );
    if (!payload.deleteProduct && (product == null || !product.active)) {
      // A later local deletion can hide this update's optimistic projection.
      final pending = await _syncPersistence.pendingEvents();
      if (!pending.any(
        (e) =>
            e.aggregateId == event.aggregateId &&
            e.eventType == ProductoActualizadoPayload.eventType &&
            ProductoActualizadoPayload.fromJson(e.payload).deleteProduct,
      )) {
        return const PendingConflict('El artículo ya no existe.');
      }
    }
    if (!payload.deleteProduct &&
        payload.after.categoriaId != null &&
        await _categoriaProjectionStore.findById(payload.after.categoriaId!) ==
            null) {
      return const PendingConflict('La categoría ya no existe.');
    }
    for (final dependency
        in payload.deleteProduct
            ? <ProductoCreadoInventarioDependencia>[]
            : payload.after.dependenciasInventario) {
      final item = await _inventoryProjectionStore?.findItemById(
        dependency.refId,
      );
      if (item == null || !item.active) {
        return const PendingConflict(
          'El recurso de inventario ya no está activo.',
        );
      }
    }
    final base = await _dependencies.resolveBase(
      baseEventId: payload.baseEventId,
      fallbackServerSequence: event.baseServerSequence,
    );
    if (base.waitsForLocalDependency || base.serverSequence == null) {
      return null;
    }
    final official = await _syncedEventHistory.eventsForAggregateAfter(
      aggregateType: ProductoActualizadoPayload.aggregateType,
      aggregateId: event.aggregateId,
      serverSequence: base.serverSequence!,
    );
    if (official.any((e) => e.eventId != event.eventId)) {
      return const PendingConflict(
        'El artículo cambió oficialmente desde la base local.',
      );
    }
    return null;
  }

  Future<PendingConflict?> _productoCreadoConflict(SyncEvent event) async {
    final store = _productoProjectionStore;
    if (store == null) return null;

    final existing = await store.findProductById(event.aggregateId);
    if (existing != null && existing.createdEventId != event.eventId) {
      return PendingConflict(
        'Ya existe un artículo oficial con id ${event.aggregateId}.',
      );
    }
    final payload = ProductoCreadoPayload.fromJson(event.payload);
    for (final payloadVariant in payload.variantes) {
      final variant = await store.findVariantById(payloadVariant.id);
      if (variant != null && variant.createdEventId != event.eventId) {
        return PendingConflict(
          'Ya existe una variante oficial con id ${payloadVariant.id}.',
        );
      }
      for (final component in payloadVariant.componentesReceta) {
        final item = await _inventoryProjectionStore?.findItemById(
          component.inventoryItemId,
        );
        if (item == null || !item.active) {
          return const PendingConflict(
            'Ya no existe un recurso activo para un componente de receta.',
          );
        }
      }
      final inventoryItemId = payloadVariant.inventoryItemId;
      if (inventoryItemId == null) continue;
      final linked = await store.findVariantByInventoryItemId(inventoryItemId);
      if (linked != null && linked.createdEventId != event.eventId) {
        return PendingConflict(
          'El recurso $inventoryItemId ya está vinculado a otra variante.',
        );
      }
      final item = await _inventoryProjectionStore?.findItemById(
        inventoryItemId,
      );
      if (item == null || !item.active) {
        return const PendingConflict(
          'Ya no existe un recurso activo para una variante del artículo.',
        );
      }
    }
    if (payload.categoriaId != null &&
        await _categoriaProjectionStore.findById(payload.categoriaId!) ==
            null) {
      return const PendingConflict(
        'Ya no existe la categoría elegida para el artículo.',
      );
    }
    return null;
  }

  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {
    switch (event.eventType) {
      case ProductoActualizadoPayload.eventType:
        final payload = ProductoActualizadoPayload.fromJson(event.payload);
        await _productoProjectionStore?.applyUpdate(
          event,
          payload.before,
          restore: true,
          baseEventId: payload.baseEventId,
        );
      case ProductoCreadoPayload.eventType:
        await _productoProjectionStore?.deleteCreatedByEvent(event.eventId);
    }
  }
}
