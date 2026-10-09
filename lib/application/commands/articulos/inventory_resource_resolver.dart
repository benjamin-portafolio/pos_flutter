import '../../../domain/articulos/sale_configuration.dart';
import '../../sync/payloads/producto_creado_payload.dart';
import '../../sync/payloads/producto_actualizado_payload.dart';
import '../../sync/projections/inventory_projection_store.dart';
import '../../sync/projections/variant_inventory_memory_store.dart';
import '../../sync/projections/variant_inventory_tracking_store.dart';
import 'recurso_recuperacion_resultado.dart';

/// Resuelve identidad usando memoria o evidencia causal, nunca nombre/reloj.
class InventoryResourceResolver {
  const InventoryResourceResolver({
    required VariantInventoryMemoryStore memoryStore,
    required VariantInventoryTrackingStore trackingStore,
    required InventoryProjectionStore inventoryStore,
  }) : _memoryStore = memoryStore,
       _trackingStore = trackingStore,
       _inventoryStore = inventoryStore;
  final VariantInventoryMemoryStore _memoryStore;
  final VariantInventoryTrackingStore _trackingStore;
  final InventoryProjectionStore _inventoryStore;

  Future<List<VariantTrackingResource>> selectionCandidates(
    String variantId, {
    required String requiredUnitId,
    required SaleConfiguration saleConfiguration,
  }) async {
    final result = <VariantTrackingResource>[];
    for (final candidate in await _trackingStore.selectionResources(
      variantId,
    )) {
      if (await _validateCandidate(
            variantId: variantId,
            inventoryItemId: candidate.id,
            requiredUnitId: requiredUnitId,
            saleConfiguration: saleConfiguration,
          )
          is RecursoRecuperableResultado) {
        result.add(candidate);
      }
    }
    return result;
  }

  Future<RecursoRecuperacionResultado> resolve({
    required String variantId,
    required String? currentInventoryItemId,
    required String requiredUnitId,
    required SaleConfiguration saleConfiguration,
    String? selectedInventoryItemId,
  }) async {
    Future<RecursoRecuperacionResultado> validate(String id) =>
        _validateCandidate(
          variantId: variantId,
          inventoryItemId: id,
          requiredUnitId: requiredUnitId,
          saleConfiguration: saleConfiguration,
        );
    if (currentInventoryItemId != null) {
      if (selectedInventoryItemId != null &&
          selectedInventoryItemId != currentInventoryItemId) {
        return const RecursoNoDisponibleResultado(
          motivo: 'La selección no coincide con el recurso vinculado.',
        );
      }
      return validate(currentInventoryItemId);
    }
    final memory = await _memoryStore.findByVariantId(variantId);
    if (memory != null) {
      if (selectedInventoryItemId != null &&
          selectedInventoryItemId != memory.inventoryItemId) {
        return const RecursoNoDisponibleResultado(
          motivo: 'La selección no coincide con el recurso recordado.',
        );
      }
      return validate(memory.inventoryItemId);
    }
    if (selectedInventoryItemId != null) {
      return validate(selectedInventoryItemId);
    }

    final history = await _trackingStore.historyForVariant(variantId);
    final evidence = _reconstruct(history, variantId);
    if (evidence.complete && evidence.inventoryItemId != null) {
      return validate(evidence.inventoryItemId!);
    }
    final origin = await _trackingStore.resourcesByOriginVariant(variantId);
    if (origin.length == 1) return validate(origin.single.id);
    if (origin.length > 1 || !evidence.complete) {
      return const RecursoSeleccionRequeridaResultado(
        motivo:
            'La historia anterior está incompleta o hay varios recursos posibles. Selecciona el recurso que recuperarás.',
      );
    }
    // La variante es nueva o una cadena íntegra prueba que nunca tuvo recurso.
    return const RecursoNuevoResultado();
  }

  ({bool complete, String? inventoryItemId}) _reconstruct(
    VariantTrackingHistory history,
    String variantId,
  ) {
    if (!history.variantExists) return (complete: true, inventoryItemId: null);
    final root = history.events
        .where(
          (e) =>
              e.eventId == history.createdEventId &&
              e.eventType == ProductoCreadoPayload.eventType,
        )
        .firstOrNull;
    if (root == null || history.currentState == null) {
      return (complete: false, inventoryItemId: null);
    }
    try {
      var state = ProductoCreadoPayload.fromJson(root.payload);
      var head = root.eventId;
      var version = root.baseVersion ?? 1;
      String? lastItem = state.variantes
          .where((v) => v.id == variantId)
          .firstOrNull
          ?.inventoryItemId;
      final visited = <String>{root.eventId};
      final updates = {
        for (final e in history.events.where(
          (e) => e.eventType == ProductoActualizadoPayload.eventType,
        ))
          e.eventId: ProductoActualizadoPayload.fromJson(e.payload),
      };
      while (true) {
        final next = history.events
            .where(
              (e) =>
                  !visited.contains(e.eventId) &&
                  updates[e.eventId]?.baseEventId == head,
            )
            .toList();
        if (next.isEmpty) break;
        if (next.length != 1) return (complete: false, inventoryItemId: null);
        final event = next.single;
        final update = updates[event.eventId]!;
        if (event.baseVersion != version ||
            update.deleteProduct ||
            !ProductoActualizadoPayload.sameEditingBase(state, update.before)) {
          return (complete: false, inventoryItemId: null);
        }
        final prior = update.before.variantes
            .where((v) => v.id == variantId)
            .firstOrNull
            ?.inventoryItemId;
        lastItem =
            update.after.variantes
                .where((v) => v.id == variantId)
                .firstOrNull
                ?.inventoryItemId ??
            prior ??
            lastItem;
        state = update.after;
        head = event.eventId;
        version++;
        visited.add(event.eventId);
      }
      if (updates.keys.any((id) => !visited.contains(id)) ||
          !ProductoActualizadoPayload.sameEditingBase(
            state,
            history.currentState!,
          )) {
        return (complete: false, inventoryItemId: null);
      }
      return (complete: true, inventoryItemId: lastItem);
    } on FormatException {
      return (complete: false, inventoryItemId: null);
    }
  }

  Future<RecursoRecuperacionResultado> _validateCandidate({
    required String variantId,
    required String inventoryItemId,
    required String requiredUnitId,
    required SaleConfiguration saleConfiguration,
  }) async {
    RecursoNoDisponibleResultado unavailable(String reason) =>
        RecursoNoDisponibleResultado(motivo: reason);
    final item = await _inventoryStore.findItemById(inventoryItemId);
    if (item == null) {
      if (await _trackingStore.hasAppliedDiscard(inventoryItemId)) {
        return const RecursoNuevoResultado();
      }
      return unavailable(
        'El recurso anterior falta y no hay prueba de un descarte aplicado.',
      );
    }
    if (!item.active) return unavailable('El recurso está inactivo.');
    if (item.originVariantId != null && item.originVariantId != variantId) {
      return unavailable('El recurso fue generado para otra variante.');
    }
    if ((await _trackingStore.directLinkedVariantIds(
      inventoryItemId,
    )).any((id) => id != variantId)) {
      return unavailable('El recurso ya está vinculado a otra variante.');
    }
    if (await _trackingStore.balanceOf(inventoryItemId) == null) {
      return unavailable('Falta el balance del recurso; requiere revisión.');
    }
    final unit = await _inventoryStore.findUnitById(item.defaultUnitId);
    if (unit == null || !unit.active) {
      return unavailable('La unidad del recurso no existe o está inactiva.');
    }
    if (item.defaultUnitId != requiredUnitId) {
      return unavailable(
        'La unidad no coincide con la unidad elegida para seguimiento.',
      );
    }
    switch (saleConfiguration) {
      case UnitSaleConfiguration():
        if (unit.dimension != 'count' || unit.atomicFactor != 1) {
          return unavailable(
            'La venta por unidad requiere existencias en piezas.',
          );
        }
      case MeasuredSaleConfiguration():
        final saleUnit = await _inventoryStore.findUnitById(
          saleConfiguration.saleUnitId,
        );
        if (saleUnit == null ||
            !saleUnit.active ||
            saleUnit.dimension != unit.dimension) {
          return unavailable(
            'La unidad de inventario no es compatible con la venta medida.',
          );
        }
    }
    return RecursoRecuperableResultado(inventoryItemId: inventoryItemId);
  }
}
