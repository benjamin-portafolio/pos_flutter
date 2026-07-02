import 'dart:async';

import 'sync_health_service.dart';
import 'sync_pull_service.dart';
import 'sync_push_service.dart';
import 'sync_socket_listener.dart';

class SyncOrchestrator {
  SyncOrchestrator({
    required SyncHealthService healthService,
    required SyncPullService pullService,
    required SyncPushService pushService,
    required SyncSocketListener socketListener,
  }) : _healthService = healthService,
       _pullService = pullService,
       _pushService = pushService,
       _socketListener = socketListener;

  final SyncHealthService _healthService;
  final SyncPullService _pullService;
  final SyncPushService _pushService;
  final SyncSocketListener _socketListener;

  StreamSubscription<SyncEventsAvailableNotice>? _eventsAvailableSubscription;
  bool _isPullingAvailableEvents = false;
  bool _pullRequestedWhileBusy = false;
  int? _latestPullTarget;

  Future<SyncHealthCheck> testConnection() {
    return _healthService.check();
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

  Future<SyncPullReport> pullIfBehind(int latestServerSequence) {
    return _pullService.pullIfBehind(latestServerSequence);
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
