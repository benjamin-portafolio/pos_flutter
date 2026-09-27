import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/projections/financial_entry_projection.dart';
import '../../../application/sync/projections/financial_entry_projection_store.dart';
import 'app_database.dart';

/// Adaptador Drift de la proyección de registros financieros. `atomic` provee
/// la transacción del command service. No hay borrado ni reaplicación de
/// montos: el eco solo avanza `last_server_sequence` por `created_event_id`.
class DriftFinancialEntryProjectionStore
    implements FinancialEntryProjectionStore {
  DriftFinancialEntryProjectionStore({
    required AppDatabase db,
    required FinancialEntryDao dao,
  }) : _db = db,
       _dao = dao;

  final AppDatabase _db;
  final FinancialEntryDao _dao;

  @override
  Future<T> atomic<T>(Future<T> Function() action) => _db.transaction(action);

  @override
  Future<FinancialEntryProjection?> findById(String id) async {
    final row = await _dao.findById(id);
    if (row == null) return null;
    return FinancialEntryProjection(
      id: row.id,
      categoryId: row.categoryId,
      categoryNameSnapshot: row.categoryNameSnapshot,
      direction: row.direction,
      nature: row.nature,
      amountMinor: row.amountMinor,
      currency: row.currency,
      method: row.method,
      occurredAtMs: row.occurredAtMs,
      notes: row.notes,
      reference: row.reference,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }

  @override
  Future<SyncEvent?> entryEvent(String id) async {
    final row = await _dao.findById(id);
    if (row == null || row.createdEventId == null) return null;
    final event = await (_db.select(_db.events)
          ..where((t) => t.eventId.equals(row.createdEventId!)))
        .getSingleOrNull();
    if (event == null) return null;
    return SyncEvent(
      eventId: event.eventId,
      aggregateType: event.aggregateType,
      aggregateId: event.aggregateId,
      eventType: event.eventType,
      deviceId: event.deviceId,
      userId: event.userId,
      createdAtLocal: event.createdAtLocal,
      payload: Map<String, Object?>.from(jsonDecode(event.payload) as Map),
    );
  }

  @override
  Future<void> insert(FinancialEntryProjection p) => _dao.upsert(
    FinancialEntriesCompanion.insert(
      id: p.id,
      categoryId: p.categoryId,
      categoryNameSnapshot: p.categoryNameSnapshot,
      direction: p.direction,
      nature: p.nature,
      amountMinor: p.amountMinor,
      currency: p.currency,
      method: p.method,
      occurredAtMs: p.occurredAtMs,
      notes: Value(p.notes),
      reference: Value(p.reference),
      active: Value(p.active),
      version: Value(p.version),
      createdEventId: Value(p.createdEventId),
      lastEventId: Value(p.lastEventId),
      lastServerSequence: Value(p.lastServerSequence),
    ),
  );

  @override
  Future<void> advanceServerSequence(String eventId, int serverSequence) =>
      _dao.advanceServerSequence(eventId, serverSequence);
}