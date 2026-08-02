import 'dart:convert';

import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/sync_persistence.dart';
import '../../../application/sync/synced_event_history.dart';
import 'app_database.dart';

class DriftSyncPersistence implements SyncPersistence, SyncedEventHistory {
  DriftSyncPersistence({
    required EventDao eventDao,
    required EventRefDao eventRefDao,
    required SyncCheckpointDao syncCheckpointDao,
  }) : _eventDao = eventDao,
       _eventRefDao = eventRefDao,
       _syncCheckpointDao = syncCheckpointDao;

  final EventDao _eventDao;
  final EventRefDao _eventRefDao;
  final SyncCheckpointDao _syncCheckpointDao;

  @override
  Future<List<SyncEvent>> pendingEvents() async {
    final records = await _eventDao.obtenerEventosPendientes();
    return records.map(_eventFromRecord).toList();
  }

  @override
  Future<SyncEvent?> eventById(String eventId) async {
    final record = await _eventDao.obtenerEventoPorId(eventId);
    return record == null ? null : _eventFromRecord(record);
  }

  @override
  Future<List<SyncEvent>> eventsForAggregateAfter({
    required String aggregateType,
    required String aggregateId,
    required int serverSequence,
  }) async {
    final records = await _eventDao
        .obtenerEventosSincronizadosDelAgregadoDespuesDe(
          aggregateType: aggregateType,
          aggregateId: aggregateId,
          serverSequence: serverSequence,
        );
    return records.map(_eventFromRecord).toList();
  }

  @override
  Future<List<SyncEvent>> eventsByTypeAfter({
    required String eventType,
    required int serverSequence,
  }) async {
    final records = await _eventDao.obtenerEventosSincronizadosPorTipoDespuesDe(
      eventType: eventType,
      serverSequence: serverSequence,
    );
    return records.map(_eventFromRecord).toList();
  }

  @override
  Future<List<SyncEvent>> unreportedConflictEvents() async {
    final records = await _eventDao.obtenerConflictosNoReportados();
    return records.map(_eventFromRecord).toList();
  }

  @override
  Stream<List<SyncEvent>> watchPendingEvents() {
    return _eventDao.watchEventosPendientes().map(
      (records) => records.map(_eventFromRecord).toList(),
    );
  }

  @override
  Future<void> updateEventSyncStatus(
    String eventId,
    String status, {
    int? serverSequence,
    DateTime? serverTime,
    String? rejectionReason,
  }) async {
    await _eventDao.actualizarEstadoSincronizacion(
      eventId,
      status,
      serverSequence: serverSequence,
      serverTime: serverTime,
      rejectionReason: rejectionReason,
    );
  }

  @override
  Future<List<StoredEventRef>> refsForEvents(List<String> eventIds) async {
    final refs = await _eventRefDao.obtenerReferenciasPorEventos(eventIds);
    return refs.map(_refFromRecord).toList();
  }

  @override
  Future<void> markRefsSynced(String eventId, int serverSequence) async {
    await _eventRefDao.actualizarReferenciasSincronizadas(
      eventId,
      serverSequence,
    );
  }

  @override
  Future<int> lastFullPullServerSequence() {
    return _syncCheckpointDao.obtenerLastFullPullServerSequence();
  }

  @override
  Future<int> lastPreflightServerSequence() {
    return _syncCheckpointDao.obtenerLastPreflightServerSequence();
  }

  @override
  Future<void> updateLastFullPullServerSequence(
    int serverSequence, {
    DateTime? pulledAt,
  }) {
    return _syncCheckpointDao.actualizarLastFullPullServerSequence(
      serverSequence,
      pulledAt: pulledAt,
    );
  }

  @override
  Future<void> updateLastPreflightServerSequence(
    int serverSequence, {
    DateTime? preflightAt,
  }) {
    return _syncCheckpointDao.actualizarLastPreflightServerSequence(
      serverSequence,
      preflightAt: preflightAt,
    );
  }

  SyncEvent _eventFromRecord(EventRecord record) {
    return SyncEvent(
      eventId: record.eventId,
      aggregateType: record.aggregateType,
      aggregateId: record.aggregateId,
      eventType: record.eventType,
      deviceId: record.deviceId,
      userId: record.userId,
      localSequence: record.localSequence,
      serverSequence: record.serverSequence,
      baseServerSequence: record.baseServerSequence,
      baseVersion: record.baseVersion,
      createdAtLocal: record.createdAtLocal,
      createdAtServer: record.createdAtServer,
      payload: _decodePayload(record.payload),
      applicationStatus: record.applicationStatus,
      deliveryStatus: record.deliveryStatus,
      rejectionReason: record.rejectionReason,
    );
  }

  StoredEventRef _refFromRecord(EventRef ref) {
    return StoredEventRef(
      eventId: ref.eventId,
      refType: ref.refType,
      refId: ref.refId,
      relationship: ref.relationship,
      source: ref.source,
      serverSequence: ref.serverSequence,
    );
  }

  Map<String, Object?> _decodePayload(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
  }
}
