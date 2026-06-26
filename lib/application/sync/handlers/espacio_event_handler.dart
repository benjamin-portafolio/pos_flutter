import 'package:drift/drift.dart';

import '../../../data/local/drift/app_database.dart';
import '../../../domain/espacios/visibilidad_espacio.dart';
import '../models/sync_event.dart';

class EspacioEventHandler {
  EspacioEventHandler(this._espacioDao);

  final EspacioDao _espacioDao;

  Future<void> applyEspacioCreado(SyncEvent event) async {
    final payload = event.payload;
    final existing = await _espacioDao.obtenerEspacioPorId(event.aggregateId);

    if (existing != null) {
      if (existing.createdEventId == event.eventId) return;

      throw StateError(
        'No se puede aplicar espacio_creado sobre un espacio existente: '
        '${event.aggregateId}',
      );
    }

    await _espacioDao.insertarEspacio(
      EspaciosCompanion.insert(
        id: event.aggregateId,
        nombre: payload['nombre']! as String,
        identificacion: Value(payload['identificacion'] as String?),
        visibilidad: visibilidadEspacioFromEventValue(payload['visibilidad']),
        active: const Value(true),
        version: Value(event.baseVersion ?? 1),
        createdEventId: Value(event.eventId),
        lastEventId: Value(event.eventId),
        lastServerSequence: Value(event.serverSequence),
      ),
    );
  }
}
