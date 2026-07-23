import 'package:uuid/uuid.dart';

import '../../domain/categorias/nombre_categoria.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/categoria_creada_payload.dart';
import 'crear_categoria_command.dart';
import 'local_command_context.dart';

class CategoriaCommandService {
  CategoriaCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
  }) : _eventStore = eventStore,
       _commandContext = commandContext;

  final LocalEventStore _eventStore;
  final LocalCommandContext _commandContext;
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
}
