import 'package:uuid/uuid.dart';

import '../../domain/categorias/direccion_movimiento_categoria.dart';
import '../../domain/categorias/nombre_categoria.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/categoria_actualizada_payload.dart';
import '../sync/payloads/categoria_creada_payload.dart';
import '../sync/payloads/categoria_movida_payload.dart';
import '../sync/projections/categoria_projection_store.dart';
import 'crear_categoria_command.dart';
import 'editar_categoria_command.dart';
import 'local_command_context.dart';
import 'mover_categoria_command.dart';

class CategoriaCommandService {
  CategoriaCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
    required CategoriaProjectionStore categoriaProjectionStore,
  }) : _eventStore = eventStore,
       _commandContext = commandContext,
       _categoriaProjectionStore = categoriaProjectionStore;

  final LocalEventStore _eventStore;
  final LocalCommandContext _commandContext;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final Uuid _uuid = const Uuid();

  Future<void> crearCategoria(CrearCategoriaCommand command) async {
    final nombre = NombreCategoria.fromInput(command.nombre);
    final categorias = await _categoriaProjectionStore.findAllOrdered();
    final categoryId = _uuid.v4();
    final payload = CategoriaCreadaPayload(
      nombre: nombre.value,
      color: command.color,
      orden: categorias.length,
    );
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: CategoriaCreadaPayload.aggregateType,
      aggregateId: categoryId,
      eventType: CategoriaCreadaPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [LocalEventRef.affects(refType: 'category', refId: categoryId)],
    );
  }

  Future<bool> editarCategoria(EditarCategoriaCommand command) async {
    final nombre = NombreCategoria.fromInput(command.nombre);
    final existing = await _categoriaProjectionStore.findById(
      command.categoriaId,
    );
    if (existing == null) {
      throw StateError(
        'No existe la categoría que se intenta editar: ${command.categoriaId}',
      );
    }

    final baseEventId = existing.lastEventId ?? existing.createdEventId;
    if (baseEventId == null) {
      throw StateError(
        'La categoría no tiene un evento base para registrar la edición.',
      );
    }
    final payload = CategoriaActualizadaPayload.fromValues(
      baseEventId: baseEventId,
      nombreAnterior: existing.nombre,
      nombreNuevo: nombre.value,
      colorAnterior: existing.color,
      colorNuevo: command.color,
    );
    if (!payload.tieneCambios) return false;

    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: CategoriaActualizadaPayload.aggregateType,
      aggregateId: existing.id,
      eventType: CategoriaActualizadaPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseServerSequence: existing.lastServerSequence,
      baseVersion: existing.version,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [LocalEventRef.affects(refType: 'category', refId: existing.id)],
    );
    return true;
  }

  Future<bool> moverCategoria(MoverCategoriaCommand command) async {
    final categorias = await _categoriaProjectionStore.findAllOrdered();
    _validateConsecutiveOrder(categorias);

    final currentIndex = categorias.indexWhere(
      (categoria) => categoria.id == command.categoriaId,
    );
    if (currentIndex < 0) {
      throw StateError(
        'No existe la categoría que se intenta mover: ${command.categoriaId}',
      );
    }

    final displacedIndex = switch (command.direccion) {
      DireccionMovimientoCategoria.arriba => currentIndex - 1,
      DireccionMovimientoCategoria.abajo => currentIndex + 1,
    };
    if (displacedIndex < 0 || displacedIndex >= categorias.length) {
      return false;
    }

    final moved = categorias[currentIndex];
    final displaced = categorias[displacedIndex];
    final movedBaseEventId = _baseEventId(moved);
    final displacedBaseEventId = _baseEventId(displaced);
    final payload = CategoriaMovidaPayload.fromValues(
      baseEventId: movedBaseEventId,
      ordenAnterior: moved.orden,
      ordenNuevo: displaced.orden,
      categoriaDesplazadaId: displaced.id,
      categoriaDesplazadaBaseEventId: displacedBaseEventId,
      categoriaDesplazadaBaseVersion: displaced.version,
      categoriaDesplazadaBaseServerSequence: displaced.lastServerSequence,
      categoriaDesplazadaOrdenAnterior: displaced.orden,
      categoriaDesplazadaOrdenNuevo: moved.orden,
    );
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: CategoriaMovidaPayload.aggregateType,
      aggregateId: moved.id,
      eventType: CategoriaMovidaPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseServerSequence: moved.lastServerSequence,
      baseVersion: moved.version,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(refType: 'category', refId: moved.id),
        LocalEventRef.affects(refType: 'category', refId: displaced.id),
      ],
    );
    return true;
  }

  String _baseEventId(CategoriaProjection projection) {
    final value = projection.lastEventId ?? projection.createdEventId;
    if (value == null) {
      throw StateError(
        'La categoría ${projection.id} no tiene un evento base.',
      );
    }
    return value;
  }

  void _validateConsecutiveOrder(List<CategoriaProjection> categorias) {
    for (var index = 0; index < categorias.length; index++) {
      if (categorias[index].orden != index) {
        throw StateError(
          'El orden de categorías debe ser consecutivo antes de mover.',
        );
      }
    }
  }
}
