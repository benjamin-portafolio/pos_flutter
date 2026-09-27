import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/projections/financial_category_projection.dart';
import '../../../application/sync/projections/financial_category_projection_store.dart';
import 'app_database.dart';

/// Adaptador Drift de la proyección de categorías financieras. `atomic` provee
/// la transacción del command service; el upsert reemplaza la alta local por
/// el oficial conservando las entries que referencian la categoría.
class DriftFinancialCategoryProjectionStore
    implements FinancialCategoryProjectionStore {
  DriftFinancialCategoryProjectionStore({
    required AppDatabase db,
    required FinancialCategoryDao dao,
  }) : _db = db,
       _dao = dao;

  final AppDatabase _db;
  final FinancialCategoryDao _dao;

  @override
  Future<T> atomic<T>(Future<T> Function() action) => _db.transaction(action);

  @override
  Future<FinancialCategoryProjection?> findById(String id) async {
    final row = await _dao.findById(id);
    if (row == null) return null;
    return FinancialCategoryProjection(
      id: row.id,
      name: row.name,
      direction: row.direction,
      nature: row.nature,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }

  @override
  Future<SyncEvent?> categoryEvent(String id) async {
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
  Future<void> insert(FinancialCategoryProjection p) => _dao.upsert(
    FinancialCategoriesCompanion.insert(
      id: p.id,
      name: p.name,
      direction: p.direction,
      nature: p.nature,
      active: Value(p.active),
      version: Value(p.version),
      createdEventId: Value(p.createdEventId),
      lastEventId: Value(p.lastEventId),
      lastServerSequence: Value(p.lastServerSequence),
    ),
  );

  @override
  Future<void> advanceServerSequence(String id, int serverSequence) =>
      _dao.advanceServerSequence(id, serverSequence);
}