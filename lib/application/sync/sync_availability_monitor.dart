import 'dart:async';

import 'exceptions/sync_health_exception.dart';
import 'exceptions/sync_pull_exception.dart';
import 'exceptions/sync_push_exception.dart';
import 'models/sync_availability_snapshot.dart';
import 'models/sync_event.dart';
import 'models/sync_health_check.dart';
import 'sync_health_service.dart';
import 'sync_orchestrator.dart';
import 'sync_persistence.dart';

class SyncAvailabilityMonitor {
  SyncAvailabilityMonitor({
    required SyncPersistence syncPersistence,
    required SyncHealthService healthService,
    required SyncOrchestrator orchestrator,
    List<Duration> retryDelays = defaultRetryDelays,
  }) : _syncPersistence = syncPersistence,
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

  final SyncPersistence _syncPersistence;
  final SyncHealthService _healthService;
  final SyncOrchestrator _orchestrator;
  final List<Duration> _retryDelays;
  final _snapshots = StreamController<SyncAvailabilitySnapshot>.broadcast();

  StreamSubscription<List<SyncEvent>>? _pendingEventsSubscription;
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
    _pendingEventsSubscription = _syncPersistence.watchPendingEvents().listen((
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
      final pendingEvents = await _syncPersistence.pendingEvents();
      if (pendingEvents.isNotEmpty) {
        await _orchestrator.pushPendingEvents(
          latestServerSequence: health.latestServerSequence,
        );
      } else {
        final latestServerSequence = health.latestServerSequence;
        if (latestServerSequence == null) {
          await _orchestrator.pullAvailableEvents();
        } else {
          await _orchestrator.pullIfBehind(latestServerSequence);
        }
      }

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
