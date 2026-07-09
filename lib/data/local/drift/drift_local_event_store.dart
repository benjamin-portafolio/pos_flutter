import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../application/config/app_config.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../application/sync/event_processor.dart';
import '../../../application/sync/local_event_store.dart';
import '../../../application/sync/models/sync_event.dart';
import 'app_database.dart';

class DriftLocalEventStore implements LocalEventStore {
  DriftLocalEventStore({
    required AppDatabase db,
    required EventDao eventDao,
    required EventRefDao eventRefDao,
    required EventProcessor eventProcessor,
    AppConfigController? appConfigController,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _eventDao = eventDao,
       _eventRefDao = eventRefDao,
       _eventProcessor = eventProcessor,
       _appConfigController = appConfigController,
       _uuid = uuid;

  static const _localPendingSource = 'local_pending';

  final AppDatabase _db;
  final EventDao _eventDao;
  final EventRefDao _eventRefDao;
  final EventProcessor _eventProcessor;
  final AppConfigController? _appConfigController;
  final Uuid _uuid;

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) async {
    if (refs.isEmpty) {
      throw ArgumentError.value(
        refs,
        'refs',
        'Debe incluir al menos una referencia al agregado principal.',
      );
    }

    final localEvent = _localEventForCurrentMode(event);

    await _db.transaction(() async {
      await _eventDao.insertarEvento(_eventCompanionFrom(localEvent));
      await _eventRefDao.insertarReferencias(
        refs.map((ref) => _eventRefCompanionFrom(localEvent, ref)).toList(),
      );
      await _eventProcessor.apply(localEvent);
    });
  }

  SyncEvent _localEventForCurrentMode(SyncEvent event) {
    final mode = _appConfigController?.mode;
    if (mode == AppMode.standalone) {
      return event.copyWith(
        applicationStatus: 'applied',
        deliveryStatus: 'not_required',
      );
    }

    return event.copyWith(
      applicationStatus: 'applied',
      deliveryStatus: event.deliveryStatus == 'not_required'
          ? 'pending'
          : event.deliveryStatus,
    );
  }

  EventsCompanion _eventCompanionFrom(SyncEvent event) {
    return EventsCompanion.insert(
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
      applicationStatus: Value(event.applicationStatus),
      deliveryStatus: Value(event.deliveryStatus),
      rejectionReason: Value(event.rejectionReason),
    );
  }

  EventRefsCompanion _eventRefCompanionFrom(
    SyncEvent event,
    LocalEventRef ref,
  ) {
    return EventRefsCompanion.insert(
      eventRefId: _uuid.v4(),
      eventId: event.eventId,
      refType: ref.refType,
      refId: ref.refId,
      relationship: ref.relationship,
      source: _localPendingSource,
    );
  }
}
