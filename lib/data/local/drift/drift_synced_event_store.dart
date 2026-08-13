import 'package:drift/drift.dart';

import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/synced_event_store.dart';
import 'app_database.dart';

class DriftSyncedEventStore implements SyncedEventStore {
  DriftSyncedEventStore({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> applySyncedEvents(
    List<SyncEvent> events, {
    required Future<void> Function(SyncEvent event) applyEvent,
    required Future<void> Function(SyncEvent event) acknowledgeEcho,
    Future<void> Function(SyncEvent event)? prepareEvent,
    Future<void> Function()? afterApply,
  }) async {
    if (events.isEmpty) {
      if (afterApply != null) {
        await _db.transaction(afterApply);
      }
      return;
    }

    await _db.transaction(() async {
      for (final event in events) {
        // Un evento ya aplicado puede volver como eco después de que otras
        // acciones locales hayan avanzado la proyección.
        final alreadyAppliedLocally = await _isAlreadyApplied(event.eventId);
        if (!alreadyAppliedLocally && prepareEvent != null) {
          await prepareEvent(event);
        }
        await _upsertSyncedEvent(event);
        await _markEventRefsSynced(event);
        if (alreadyAppliedLocally) {
          await acknowledgeEcho(event);
        } else {
          await applyEvent(event);
        }
      }

      if (afterApply != null) {
        await afterApply();
      }
    });
  }

  Future<void> _upsertSyncedEvent(SyncEvent event) async {
    final insert = EventsCompanion.insert(
      eventId: event.eventId,
      aggregateType: event.aggregateType,
      aggregateId: event.aggregateId,
      eventType: event.eventType,
      deviceId: event.deviceId,
      userId: event.userId,
      serverSequence: Value(event.serverSequence),
      baseServerSequence: Value(event.baseServerSequence),
      baseVersion: Value(event.baseVersion),
      createdAtLocal: event.createdAtLocal,
      createdAtServer: Value(event.createdAtServer),
      payload: event.payloadJson,
      applicationStatus: const Value('applied'),
      deliveryStatus: const Value('delivered'),
      rejectionReason: Value(event.rejectionReason),
    );

    await _db.into(_db.events).insert(insert, mode: InsertMode.insertOrIgnore);
    await (_db.update(
      _db.events,
    )..where((t) => t.eventId.equals(event.eventId))).write(
      EventsCompanion(
        aggregateType: Value(event.aggregateType),
        aggregateId: Value(event.aggregateId),
        eventType: Value(event.eventType),
        deviceId: Value(event.deviceId),
        userId: Value(event.userId),
        serverSequence: Value(event.serverSequence),
        baseServerSequence: Value(event.baseServerSequence),
        baseVersion: Value(event.baseVersion),
        createdAtLocal: Value(event.createdAtLocal),
        createdAtServer: Value(event.createdAtServer),
        payload: Value(event.payloadJson),
        applicationStatus: const Value('applied'),
        deliveryStatus: const Value('delivered'),
        rejectionReason: Value(event.rejectionReason),
      ),
    );
  }

  Future<bool> _isAlreadyApplied(String eventId) async {
    final existing = await (_db.select(
      _db.events,
    )..where((event) => event.eventId.equals(eventId))).getSingleOrNull();
    return existing?.applicationStatus == 'applied';
  }

  Future<void> _markEventRefsSynced(SyncEvent event) async {
    final serverSequence = event.serverSequence;
    if (serverSequence == null) return;

    await (_db.update(
      _db.eventRefs,
    )..where((ref) => ref.eventId.equals(event.eventId))).write(
      EventRefsCompanion(
        serverSequence: Value(serverSequence),
        source: const Value('server'),
      ),
    );
  }
}
