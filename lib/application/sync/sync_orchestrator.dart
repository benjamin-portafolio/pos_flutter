import 'dart:async';

import '../../data/local/drift/app_database.dart';
import 'sync_push_service.dart';
import 'sync_socket_listener.dart';

class SyncOrchestrator {
  SyncOrchestrator({
    required EventDao eventDao,
    required SyncPushService pushService,
    required SyncSocketListener socketListener,
  }) : _eventDao = eventDao,
       _pushService = pushService,
       _socketListener = socketListener;

  final EventDao _eventDao;
  final SyncPushService _pushService;
  final SyncSocketListener _socketListener;

  StreamSubscription<List<EventRecord>>? _pendingEventsSubscription;
  bool _isPushingPendingEvents = false;
  bool _pushRequestedWhileBusy = false;

  bool get isAutoPushActive => _pendingEventsSubscription != null;

  Future<SyncConnectionCheck> testConnection() {
    return _pushService.testConnection();
  }

  Future<SyncPushReport> pushPendingEvents() {
    return _pushService.pushPendingEvents();
  }

  void startAutoPush() {
    if (isAutoPushActive) return;

    _pendingEventsSubscription = _eventDao.watchEventosPendientes().listen((
      events,
    ) {
      if (events.isEmpty) return;

      _schedulePendingEventsPush();
    });
  }

  Future<void> stopAutoPush() async {
    final subscription = _pendingEventsSubscription;
    if (subscription == null) return;

    _pendingEventsSubscription = null;
    await subscription.cancel();
  }

  void startRealtimeListener() {
    _socketListener.start();
  }

  void stopRealtimeListener() {
    _socketListener.stop();
  }

  void reconnectRealtimeListenerIfActive() {
    _socketListener.reconnectIfActive();
  }

  void _schedulePendingEventsPush() {
    if (_isPushingPendingEvents) {
      _pushRequestedWhileBusy = true;
      return;
    }

    unawaited(_pushPendingEventsUntilIdle());
  }

  Future<void> _pushPendingEventsUntilIdle() async {
    _isPushingPendingEvents = true;

    try {
      var keepPushing = true;
      while (keepPushing) {
        _pushRequestedWhileBusy = false;

        try {
          await _pushService.pushPendingEvents();
        } on SyncPushException {
          _pushRequestedWhileBusy = false;
        }

        keepPushing = _pushRequestedWhileBusy;
      }
    } finally {
      _isPushingPendingEvents = false;
    }
  }
}
