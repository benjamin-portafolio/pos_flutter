import 'package:drift/drift.dart';

import '../../data/local/drift/app_database.dart';
import 'event_processor.dart';
import 'models/sync_event.dart';

class RemoteEventApplier {
  RemoteEventApplier({
    required AppDatabase db,
    required EventProcessor eventProcessor,
  }) : _db = db,
       _eventProcessor = eventProcessor;

  final AppDatabase _db;
  final EventProcessor _eventProcessor;

  Future<void> applySyncedEvents(
    List<SyncEvent> events, {
    Future<void> Function()? afterApply,
  }) async {
    if (events.isEmpty) {
      if (afterApply != null) {
        await afterApply();
      }
      return;
    }

    await _db.transaction(() async {
      for (final event in events) {
        await _upsertSyncedEvent(event);
        await _eventProcessor.apply(event);
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
      syncStatus: const Value('synced'),
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
        syncStatus: const Value('synced'),
      ),
    );
  }
}
