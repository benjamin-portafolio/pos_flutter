import 'dart:async';

import '../../data/local/drift/app_database.dart';
import 'sync_pull_service.dart';
import 'sync_push_service.dart';
import 'sync_socket_listener.dart';

class SyncOrchestrator {
  SyncOrchestrator({
    required EventDao eventDao,
    required SyncPullService pullService,
    required SyncPushService pushService,
    required SyncSocketListener socketListener,
  }) : _eventDao = eventDao,
       _pullService = pullService,
       _pushService = pushService,
       _socketListener = socketListener;

  final EventDao _eventDao;
  final SyncPullService _pullService;
  final SyncPushService _pushService;
  final SyncSocketListener _socketListener;

  StreamSubscription<List<EventRecord>>? _pendingEventsSubscription;
  StreamSubscription<SyncEventsAvailableNotice>? _eventsAvailableSubscription;
  bool _isPushingPendingEvents = false;
  bool _pushRequestedWhileBusy = false;
  bool _isPullingAvailableEvents = false;
  bool _pullRequestedWhileBusy = false;
  int? _latestPullTarget;

  bool get isAutoPushActive => _pendingEventsSubscription != null;

  Future<SyncConnectionCheck> testConnection() {
    return _pushService.testConnection();
  }

  Future<SyncPushReport> pushPendingEvents() async {
    final report = await _pushService.pushPendingEvents();
    if (report.total > 0) {
      await _pullService.pullAvailableEvents();
    }

    return report;
  }

  Future<SyncPullReport> pullAvailableEvents() {
    return _pullService.pullAvailableEvents();
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
    _eventsAvailableSubscription ??= _socketListener.eventsAvailable.listen((
      notice,
    ) {
      _schedulePullIfBehind(notice.latestServerSequence);
    });
    _socketListener.start();
  }

  void stopRealtimeListener() {
    _socketListener.stop();
    final subscription = _eventsAvailableSubscription;
    if (subscription == null) return;

    _eventsAvailableSubscription = null;
    unawaited(subscription.cancel());
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
          await pushPendingEvents();
        } on SyncPushException {
          _pushRequestedWhileBusy = false;
        } on SyncPullException {
          _pushRequestedWhileBusy = false;
        }

        keepPushing = _pushRequestedWhileBusy;
      }
    } finally {
      _isPushingPendingEvents = false;
    }
  }

  void _schedulePullIfBehind(int latestServerSequence) {
    final currentTarget = _latestPullTarget;
    if (currentTarget == null || latestServerSequence > currentTarget) {
      _latestPullTarget = latestServerSequence;
    }

    if (_isPullingAvailableEvents) {
      _pullRequestedWhileBusy = true;
      return;
    }

    unawaited(_pullAvailableEventsUntilIdle());
  }

  Future<void> _pullAvailableEventsUntilIdle() async {
    _isPullingAvailableEvents = true;

    try {
      var keepPulling = true;
      while (keepPulling) {
        _pullRequestedWhileBusy = false;
        final target = _latestPullTarget;
        _latestPullTarget = null;

        if (target != null) {
          try {
            await _pullService.pullIfBehind(target);
          } on SyncPullException {
            _pullRequestedWhileBusy = false;
          }
        }

        keepPulling = _pullRequestedWhileBusy;
      }
    } finally {
      _isPullingAvailableEvents = false;
    }
  }
}
