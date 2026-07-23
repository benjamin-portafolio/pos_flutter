import 'package:uuid/uuid.dart';

import '../../domain/categorias/nombre_categoria.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/categoria_actualizada_payload.dart';
import '../sync/payloads/categoria_creada_payload.dart';
import '../sync/projections/categoria_projection_store.dart';
import 'crear_categoria_command.dart';
import 'editar_categoria_command.dart';
import 'local_command_context.dart';

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
    final categoryId = _uuid.v4();
    final payload = CategoriaCreadaPayload(
      nombre: nombre.value,
      color: command.color,
      orden: null,
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
}
