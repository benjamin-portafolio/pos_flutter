import 'package:uuid/uuid.dart';

import '../../domain/inventario/nombre_recurso_inventario.dart';
import '../../domain/inventario/tipo_movimiento_inventario.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/inventory_movement_payload.dart';
import '../sync/payloads/movimiento_inventario_registrado_payload.dart';
import '../sync/payloads/recurso_inventario_actualizado_payload.dart';
import '../sync/payloads/recurso_inventario_creado_payload.dart';
import '../sync/projections/inventory_projection_store.dart';
import 'crear_recurso_inventario_command.dart';
import 'editar_recurso_inventario_command.dart';
import 'local_command_context.dart';

class InventoryCommandService {
  InventoryCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
    required InventoryProjectionStore inventoryProjectionStore,
    Uuid uuid = const Uuid(),
  }) : _eventStore = eventStore,
       _commandContext = commandContext,
       _inventoryProjectionStore = inventoryProjectionStore,
       _uuid = uuid;

  final LocalEventStore _eventStore;
  final LocalCommandContext _commandContext;
  final InventoryProjectionStore _inventoryProjectionStore;
  final Uuid _uuid;

  Future<void> crearRecurso(CrearRecursoInventarioCommand command) async {
    final name = NombreRecursoInventario.fromInput(command.nombre).value;
    final unitId = command.defaultUnitId.trim();
    final unit = await _inventoryProjectionStore.findUnitById(unitId);
    if (unit == null || !unit.active) {
      throw ArgumentError.value(
        command.defaultUnitId,
        'defaultUnitId',
        'La unidad seleccionada no existe o está inactiva.',
      );
    }

    final delta = command.quantityDeltaAtomic;
    if (delta != null && delta <= 0) {
      throw ArgumentError.value(
        delta,
        'quantityDeltaAtomic',
        'La existencia inicial debe ser positiva.',
      );
    }
    final reason = InventoryMovementPayload.normalizeReason(
      command.movementReason,
    );
    final inventoryItemId = _uuid.v4();
    final eventId = _uuid.v4();
    final movement = delta == null
        ? null
        : InventoryMovementPayload.create(
            movementId: _uuid.v4(),
            movementType: TipoMovimientoInventario.initialBalance,
            quantityDeltaAtomic: delta,
            reason: reason,
          );
    final payload = RecursoInventarioCreadoPayload.create(
      inventoryItemId: inventoryItemId,
      name: name,
      defaultUnitId: unitId,
      initialMovement: movement,
    );
    final event = SyncEvent(
      eventId: eventId,
      aggregateType: RecursoInventarioCreadoPayload.aggregateType,
      aggregateId: inventoryItemId,
      eventType: RecursoInventarioCreadoPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(
          refType: 'inventory_item',
          refId: inventoryItemId,
        ),
        LocalEventRef.uses(refType: 'unit', refId: unitId),
        if (movement != null)
          LocalEventRef.affects(
            refType: 'inventory_movement',
            refId: movement.movementId,
          ),
      ],
    );
  }

  Future<bool> editarRecurso(EditarRecursoInventarioCommand command) async {
    final item = await _inventoryProjectionStore.findItemById(
      command.inventoryItemId.trim(),
    );
    if (item == null || !item.active) {
      throw StateError('El recurso de inventario no existe o está inactivo.');
    }
    final baseEventId = item.lastEventId ?? item.createdEventId;
    if (baseEventId == null) {
      throw StateError('El recurso no tiene un evento base trazable.');
    }

    final name = NombreRecursoInventario.fromInput(command.nombre).value;
    final hasMovement = command.quantityDeltaAtomic != null;
    if (hasMovement != (command.movementType != null)) {
      throw ArgumentError(
        'movementType y quantityDeltaAtomic deben declararse juntos.',
      );
    }
    final reason = InventoryMovementPayload.normalizeReason(
      command.movementReason,
    );
    if (!hasMovement && reason != null) {
      throw ArgumentError.value(
        command.movementReason,
        'movementReason',
        'No puede existir motivo sin movimiento.',
      );
    }

    final entries = <LocalEventAppend>[];
    var nextBaseEventId = baseEventId;
    var nextBaseVersion = item.version;
    var nextBaseServerSequence = item.lastServerSequence;

    if (name != item.name) {
      final eventId = _uuid.v4();
      final payload = RecursoInventarioActualizadoPayload.create(
        baseEventId: baseEventId,
        previousName: item.name,
        nextName: name,
      );
      entries.add(
        LocalEventAppend(
          event: SyncEvent(
            eventId: eventId,
            aggregateType: RecursoInventarioActualizadoPayload.aggregateType,
            aggregateId: item.id,
            eventType: RecursoInventarioActualizadoPayload.eventType,
            deviceId: _commandContext.deviceId,
            userId: _commandContext.userId,
            baseServerSequence: item.lastServerSequence,
            baseVersion: item.version,
            createdAtLocal: DateTime.now(),
            payload: payload.toJson(),
          ),
          refs: [
            LocalEventRef.affects(refType: 'inventory_item', refId: item.id),
          ],
        ),
      );
      nextBaseEventId = eventId;
      nextBaseVersion += 1;
      nextBaseServerSequence = null;
    }

    if (hasMovement) {
      final movement = InventoryMovementPayload.create(
        movementId: _uuid.v4(),
        movementType: command.movementType!,
        quantityDeltaAtomic: command.quantityDeltaAtomic!,
        reason: reason,
      );
      if (movement.movementType == TipoMovimientoInventario.initialBalance ||
          movement.movementType == TipoMovimientoInventario.reversal) {
        throw ArgumentError.value(
          movement.movementType,
          'movementType',
          'La edición solo admite reposiciones o correcciones manuales.',
        );
      }
      final payload = MovimientoInventarioRegistradoPayload.create(
        baseEventId: nextBaseEventId,
        movement: movement,
      );
      entries.add(
        LocalEventAppend(
          event: SyncEvent(
            eventId: _uuid.v4(),
            aggregateType: MovimientoInventarioRegistradoPayload.aggregateType,
            aggregateId: item.id,
            eventType: MovimientoInventarioRegistradoPayload.eventType,
            deviceId: _commandContext.deviceId,
            userId: _commandContext.userId,
            baseServerSequence: nextBaseServerSequence,
            baseVersion: nextBaseVersion,
            createdAtLocal: DateTime.now(),
            payload: payload.toJson(),
          ),
          refs: [
            LocalEventRef.affects(refType: 'inventory_item', refId: item.id),
            LocalEventRef.affects(
              refType: 'inventory_movement',
              refId: movement.movementId,
            ),
          ],
        ),
      );
    }

    if (entries.isEmpty) return false;
    await _eventStore.appendAndApplyAll(entries);
    return true;
  }
}
