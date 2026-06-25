import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'crear_espacio_command.dart';
import 'local_command_context.dart';
import '../sync/event_processor.dart';
import '../sync/models/sync_event.dart';
import '../sync/sync_push_service.dart';
import '../../data/local/drift/app_database.dart';

class EspacioCommandService {
  EspacioCommandService({
    required AppDatabase db,
    required EventDao eventDao,
    required EventRefDao eventRefDao,
    required EventProcessor eventProcessor,
    required LocalCommandContext commandContext,
    required SyncPushService syncPushService,
  }) : _db = db,
       _eventDao = eventDao,
       _eventRefDao = eventRefDao,
       _eventProcessor = eventProcessor,
       _commandContext = commandContext,
       _syncPushService = syncPushService;

  final AppDatabase _db;
  final EventDao _eventDao;
  final EventRefDao _eventRefDao;
  final EventProcessor _eventProcessor;
  final LocalCommandContext _commandContext;
  final SyncPushService _syncPushService;
  final Uuid _uuid = const Uuid();

  Future<void> crearEspacio(CrearEspacioCommand command) async {
    final espacioId = _uuid.v4();
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: 'espacio',
      aggregateId: espacioId,
      eventType: 'espacio_creado',
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: {
        'nombre': command.nombre,
        'identificacion': command.identificacion,
        'visibilidad': command.visibilidad.index,
      },
    );
    late final SyncEvent eventToPush;

    await _db.transaction(() async {
      final localSequence = await _eventDao.insertarEvento(
        EventsCompanion.insert(
          eventId: event.eventId,
          aggregateType: event.aggregateType,
          aggregateId: event.aggregateId,
          eventType: event.eventType,
          deviceId: event.deviceId,
          userId: event.userId,
          createdAtLocal: event.createdAtLocal,
          payload: event.payloadJson,
          baseVersion: Value(event.baseVersion),
          syncStatus: Value(event.syncStatus),
        ),
      );
      eventToPush = event.withLocalSequence(localSequence);

      await _eventRefDao.insertarReferencias([
        EventRefsCompanion.insert(
          eventRefId: _uuid.v4(),
          eventId: event.eventId,
          refType: 'espacio',
          refId: event.aggregateId,
          relationship: 'affects',
          source: 'local_pending',
        ),
        if (command.identificacion != null &&
            command.identificacion!.isNotEmpty)
          EventRefsCompanion.insert(
            eventRefId: _uuid.v4(),
            eventId: event.eventId,
            refType: 'espacio_identificacion',
            refId: command.identificacion!,
            relationship: 'requires_unique',
            source: 'local_pending',
          ),
      ]);

      await _eventProcessor.apply(event);
    });

    try {
      await _syncPushService.pushEvent(eventToPush);
    } on SyncPushException {
      // Offline-first: el evento queda pendiente para enviarse despues.
    }
  }
}
