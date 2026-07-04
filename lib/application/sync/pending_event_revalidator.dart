import 'dart:convert';

import '../../data/local/drift/app_database.dart';
import 'models/pending_revalidation_report.dart';

class PendingEventRevalidator {
  PendingEventRevalidator({
    required EventDao eventDao,
    required EspacioDao espacioDao,
  }) : _eventDao = eventDao,
       _espacioDao = espacioDao;

  final EventDao _eventDao;
  final EspacioDao _espacioDao;

  Future<PendingRevalidationReport> revalidatePendingEvents() async {
    final events = await _eventDao.obtenerEventosPendientes();
    var conflicts = 0;

    for (final event in events) {
      final hasConflict = switch (event.eventType) {
        'espacio_creado' => await _espacioCreadoHasConflict(event),
        _ => false,
      };

      if (!hasConflict) continue;

      await _eventDao.actualizarEstadoSincronizacion(event.eventId, 'conflict');
      await _espacioDao.eliminarEspacioCreadoPorEvento(event.eventId);
      conflicts++;
    }

    return PendingRevalidationReport(
      checked: events.length,
      conflicts: conflicts,
    );
  }

  Future<bool> _espacioCreadoHasConflict(EventRecord event) async {
    final existingById = await _espacioDao.obtenerEspacioPorId(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return true;
    }

    final identificacion = _readOptionalText(
      _decodePayload(event.payload)['identificacion'],
    );
    if (identificacion == null) return false;

    final existingByIdentificacion = await _espacioDao
        .obtenerEspacioPorIdentificacion(identificacion);

    return existingByIdentificacion != null &&
        existingByIdentificacion.createdEventId != event.eventId;
  }

  Map<String, Object?> _decodePayload(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }

    return const <String, Object?>{};
  }

  String? _readOptionalText(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
