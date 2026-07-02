import 'dart:async';

import '../../data/local/drift/app_database.dart';
import 'sync_health_service.dart';
import 'sync_orchestrator.dart';
import 'sync_pull_service.dart';
import 'sync_push_service.dart';

enum SyncAvailabilityStatus {
  unknown,
  checking,
  available,
  unavailable,
  misconfigured,
}

class SyncAvailabilitySnapshot {
  const SyncAvailabilitySnapshot({
    required this.status,
    this.message,
    this.latestServerSequence,
    this.nextRetryAt,
  });

  const SyncAvailabilitySnapshot.unknown()
    : status = SyncAvailabilityStatus.unknown,
      message = null,
      latestServerSequence = null,
      nextRetryAt = null;

  final SyncAvailabilityStatus status;
  final String? message;
  final int? latestServerSequence;
  final DateTime? nextRetryAt;

  bool get isAvailable => status == SyncAvailabilityStatus.available;
}

class SyncAvailabilityMonitor {
  SyncAvailabilityMonitor({
    required EventDao eventDao,
    required SyncHealthService healthService,
    required SyncOrchestrator orchestrator,
    List<Duration> retryDelays = defaultRetryDelays,
  }) : _eventDao = eventDao,
       _healthService = healthService,
       _orchestrator = orchestrator,
       _retryDelays = retryDelays;

  static const defaultRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  final EventDao _eventDao;
  final SyncHealthService _healthService;
  final SyncOrchestrator _orchestrator;
  final List<Duration> _retryDelays;
  final _snapshots = StreamController<SyncAvailabilitySnapshot>.broadcast();

  StreamSubscription<List<EventRecord>>? _pendingEventsSubscription;
  Timer? _retryTimer;
  SyncAvailabilitySnapshot _snapshot = const SyncAvailabilitySnapshot.unknown();
  Future<void>? _runningCheck;
  var _isStarted = false;
  var _runAgain = false;
  var _failureCount = 0;

  Stream<SyncAvailabilitySnapshot> get snapshots => _snapshots.stream;

  SyncAvailabilitySnapshot get snapshot => _snapshot;

  void start() {
    if (_isStarted) return;

    _isStarted = true;
    _pendingEventsSubscription = _eventDao.watchEventosPendientes().listen((
      events,
    ) {
      if (events.isEmpty) return;

      requestServerCheck();
    });

    requestServerCheck();
  }

  Future<void> stop() async {
    _isStarted = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _orchestrator.stopRealtimeListener();

    final subscription = _pendingEventsSubscription;
    _pendingEventsSubscription = null;
    await subscription?.cancel();
  }

  void requestServerCheck() {
    unawaited(checkNow());
  }

  Future<void> checkNow() {
    _retryTimer?.cancel();
    _retryTimer = null;

    final runningCheck = _runningCheck;
    if (runningCheck != null) {
      _runAgain = true;
      return runningCheck;
    }

    _runningCheck = _runChecksUntilIdle();
    return _runningCheck!;
  }

  Future<void> dispose() async {
    await stop();
    await _snapshots.close();
  }

  void markServerAvailable({int? latestServerSequence}) {
    _resetBackoff();
    _orchestrator.startRealtimeListener();
    _publish(
      SyncAvailabilitySnapshot(
        status: SyncAvailabilityStatus.available,
        message: 'Servidor disponible.',
        latestServerSequence: latestServerSequence,
      ),
    );
  }

  void markServerUnavailable(String message) {
    _handleUnavailable(message);
  }

  Future<void> _runChecksUntilIdle() async {
    try {
      do {
        _runAgain = false;
        await _checkAndSyncOnce();
      } while (_runAgain);
    } finally {
      _runningCheck = null;
    }
  }

  Future<void> _checkAndSyncOnce() async {
    _publish(
      const SyncAvailabilitySnapshot(status: SyncAvailabilityStatus.checking),
    );

    try {
      final health = await _healthService.check();
      if (!health.isAvailable) {
        _handleHealthFailure(health);
        return;
      }

      await _runSyncAfterSuccessfulHealth(health);
    } on SyncHealthException catch (error) {
      _handleUnavailable(error.message);
    } catch (error) {
      _handleUnavailable('Error comprobando disponibilidad: $error');
    }
  }

  Future<void> _runSyncAfterSuccessfulHealth(SyncHealthCheck health) async {
    _resetBackoff();

    try {
      final latestServerSequence = health.latestServerSequence;
      if (latestServerSequence == null) {
        await _orchestrator.pullAvailableEvents();
      } else {
        await _orchestrator.pullIfBehind(latestServerSequence);
      }
      await _orchestrator.pushPendingEvents();

      markServerAvailable(latestServerSequence: health.latestServerSequence);
    } on SyncPullException catch (error) {
      _handleUnavailable(error.message);
    } on SyncPushException catch (error) {
      _handleUnavailable(error.message);
    }
  }

  void _handleHealthFailure(SyncHealthCheck health) {
    if (health.isMisconfigured) {
      _resetBackoff();
      _orchestrator.stopRealtimeListener();
      _publish(
        SyncAvailabilitySnapshot(
          status: SyncAvailabilityStatus.misconfigured,
          message: health.failureMessage,
          latestServerSequence: health.latestServerSequence,
        ),
      );
      return;
    }

    _handleUnavailable(health.failureMessage);
  }

  void _handleUnavailable(String message) {
    _orchestrator.stopRealtimeListener();
    final nextRetryAt = _scheduleRetry();
    _publish(
      SyncAvailabilitySnapshot(
        status: SyncAvailabilityStatus.unavailable,
        message: message,
        nextRetryAt: nextRetryAt,
      ),
    );
  }

  DateTime _scheduleRetry() {
    final delays = _retryDelays.isEmpty ? defaultRetryDelays : _retryDelays;
    final index = _failureCount < delays.length
        ? _failureCount
        : delays.length - 1;
    final delay = delays[index];
    _failureCount++;

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      requestServerCheck();
    });

    return DateTime.now().add(delay);
  }

  void _resetBackoff() {
    _failureCount = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _publish(SyncAvailabilitySnapshot snapshot) {
    _snapshot = snapshot;
    if (!_snapshots.isClosed) {
      _snapshots.add(snapshot);
    }
  }
}
