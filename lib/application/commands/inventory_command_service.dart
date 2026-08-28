import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:uuid/uuid.dart';

import '../../domain/inventario/nombre_recurso_inventario.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/recurso_inventario_creado_payload.dart';
import '../sync/payloads/existencia_inventario_ajustada_payload.dart';
import '../sync/projections/inventory_projection_store.dart';
import 'crear_recurso_inventario_command.dart';
import 'ajustar_existencia_inventario_command.dart';
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
    if (delta == 0) {
      throw ArgumentError.value(
        delta,
        'quantityDeltaAtomic',
        'No se crean movimientos de cantidad cero.',
      );
    }
    final reason = unorm.nfkc(command.movementReason ?? '').trim();
    if (delta != null && reason.isEmpty) {
      throw ArgumentError.value(
        command.movementReason,
        'movementReason',
        'El motivo es obligatorio cuando hay una cantidad.',
      );
    }

    final inventoryItemId = _uuid.v4();
    final eventId = _uuid.v4();
    final movement = delta == null
        ? null
        : InitialInventoryMovementPayload.create(
            movementId: _uuid.v4(),
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
        LocalEventRef(refType: 'unit', refId: unitId, relationship: 'uses'),
        if (movement != null)
          LocalEventRef.affects(
            refType: 'inventory_movement',
            refId: movement.movementId,
          ),
      ],
    );
  }

  Future<void> ajustarExistencia(
    AjustarExistenciaInventarioCommand command,
  ) async {
    final inventoryItemId = command.inventoryItemId.trim();
    final item = await _inventoryProjectionStore.findItemById(inventoryItemId);
    if (item == null || !item.active) {
      throw StateError('El recurso no existe o está inactivo.');
    }
    if (command.quantityDeltaAtomic == 0) {
      throw ArgumentError.value(
        command.quantityDeltaAtomic,
        'quantityDeltaAtomic',
        'No se crean movimientos de cantidad cero.',
      );
    }
    final eventId = _uuid.v4();
    final payload = ExistenciaInventarioAjustadaPayload.create(
      inventoryItemId: inventoryItemId,
      movementId: _uuid.v4(),
      quantityDeltaAtomic: command.quantityDeltaAtomic,
      reason: command.reason,
    );
    final event = SyncEvent(
      eventId: eventId,
      aggregateType: ExistenciaInventarioAjustadaPayload.aggregateType,
      aggregateId: inventoryItemId,
      eventType: ExistenciaInventarioAjustadaPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: item.version,
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
        LocalEventRef.affects(
          refType: 'inventory_movement',
          refId: payload.movementId,
        ),
      ],
    );
  }
}
