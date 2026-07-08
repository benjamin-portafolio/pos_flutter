import 'dart:async';

import 'exceptions/sync_pull_exception.dart';
import 'models/sync_events_available_notice.dart';
import 'models/sync_health_check.dart';
import 'models/sync_pull_report.dart';
import 'models/sync_push_report.dart';
import 'sync_health_service.dart';
import 'sync_preflight_service.dart';
import 'sync_pull_service.dart';
import 'sync_conflict_report_service.dart';
import 'sync_push_service.dart';
import 'sync_socket_listener.dart';

class SyncOrchestrator {
  SyncOrchestrator({
    required SyncHealthService healthService,
    required SyncPreflightService preflightService,
    required SyncConflictReportService conflictReportService,
    required SyncPullService pullService,
    required SyncPushService pushService,
    required SyncSocketListener socketListener,
  }) : _healthService = healthService,
       _preflightService = preflightService,
       _conflictReportService = conflictReportService,
       _pullService = pullService,
       _pushService = pushService,
       _socketListener = socketListener;

  final SyncHealthService _healthService;
  final SyncPreflightService _preflightService;
  final SyncConflictReportService _conflictReportService;
  final SyncPullService _pullService;
  final SyncPushService _pushService;
  final SyncSocketListener _socketListener;

  StreamSubscription<SyncEventsAvailableNotice>? _eventsAvailableSubscription;
  StreamSubscription<void>? _connectionEstablishedSubscription;
  bool _isPullingAvailableEvents = false;
  bool _pullRequestedWhileBusy = false;
  bool _pullAllAvailableEventsRequested = false;
  int? _latestPullTarget;

  Future<SyncHealthCheck> testConnection() {
    return _healthService.check();
  }

  Future<SyncPushReport> pushPendingEvents({int? latestServerSequence}) async {
    final preflightReport = await _preflightService.preflightPendingEvents(
      latestServerSequence: latestServerSequence,
    );

    if (preflightReport.requiresFullPullBeforePush) {
      await _pullService.pullAvailableEvents();
      await _preflightService.revalidatePendingEvents();
    }

    final conflictReport = await _conflictReportService.reportLocalConflicts();
    final pushReport = await _pushService.pushPendingEvents();
    if (pushReport.total > 0) {
      await _pullService.pullAvailableEvents();
    }

    if (conflictReport.total == 0) return pushReport;

    return SyncPushReport(
      total: pushReport.total + conflictReport.total,
      synced: pushReport.synced,
      rejected: pushReport.rejected,
      conflicts: pushReport.conflicts + conflictReport.conflicts,
      pending: pushReport.pending + conflictReport.pending,
    );
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
    _connectionEstablishedSubscription ??= _socketListener.connectionEstablished
        .listen((_) {
          _schedulePullAvailableEvents();
        });
    _socketListener.start();
  }

  void stopRealtimeListener() {
    _socketListener.stop();
    final eventsAvailableSubscription = _eventsAvailableSubscription;
    final connectionEstablishedSubscription =
        _connectionEstablishedSubscription;

    _eventsAvailableSubscription = null;
    _connectionEstablishedSubscription = null;

    if (eventsAvailableSubscription != null) {
      unawaited(eventsAvailableSubscription.cancel());
    }
    if (connectionEstablishedSubscription != null) {
      unawaited(connectionEstablishedSubscription.cancel());
    }
  }

  void _schedulePullIfBehind(int latestServerSequence) {
    final currentTarget = _latestPullTarget;
    if (currentTarget == null || latestServerSequence > currentTarget) {
      _latestPullTarget = latestServerSequence;
    }

    _schedulePull();
  }

  void _schedulePullAvailableEvents() {
    _pullAllAvailableEventsRequested = true;
    _schedulePull();
  }

  void _schedulePull() {
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
        final pullAllAvailableEvents = _pullAllAvailableEventsRequested;
        _pullAllAvailableEventsRequested = false;

        if (pullAllAvailableEvents) {
          try {
            await _pullService.pullAvailableEvents();
          } on SyncPullException {
            _pullRequestedWhileBusy = false;
          }
        } else if (target != null) {
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
