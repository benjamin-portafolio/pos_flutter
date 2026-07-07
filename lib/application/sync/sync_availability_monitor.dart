import 'dart:async';

import 'device_wifi_connectivity.dart';
import 'exceptions/sync_health_exception.dart';
import 'exceptions/sync_pull_exception.dart';
import 'exceptions/sync_push_exception.dart';
import 'models/sync_availability_snapshot.dart';
import 'models/sync_event.dart';
import 'models/sync_health_check.dart';
import 'sync_health_service.dart';
import 'sync_orchestrator.dart';
import 'sync_persistence.dart';
import 'sync_server_detection_config.dart';

class SyncAvailabilityMonitor {
  SyncAvailabilityMonitor({
    required SyncPersistence syncPersistence,
    required SyncHealthService healthService,
    required SyncOrchestrator orchestrator,
    required SyncServerDetectionConfig serverDetectionConfig,
    required DeviceWifiConnectivity wifiConnectivity,
    List<Duration> retryDelays = defaultRetryDelays,
  }) : _syncPersistence = syncPersistence,
       _healthService = healthService,
       _orchestrator = orchestrator,
       _serverDetectionConfig = serverDetectionConfig,
       _wifiConnectivity = wifiConnectivity,
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
  final SyncServerDetectionConfig _serverDetectionConfig;
  final DeviceWifiConnectivity _wifiConnectivity;
  final List<Duration> _retryDelays;
  final _snapshots = StreamController<SyncAvailabilitySnapshot>.broadcast();

  StreamSubscription<List<SyncEvent>>? _pendingEventsSubscription;
  StreamSubscription<bool>? _wifiConnectionSubscription;
  StreamSubscription<bool>? _serverDetectionSubscription;
  Timer? _retryTimer;
  SyncAvailabilitySnapshot _snapshot = const SyncAvailabilitySnapshot.unknown();
  Future<void>? _runningCheck;
  bool? _isWifiConnected;
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
    _wifiConnectionSubscription = _wifiConnectivity.wifiConnectionChanges
        .listen(_handleWifiConnectionChanged);
    _serverDetectionSubscription = _serverDetectionConfig
        .requireWifiForServerDetectionChanges
        .listen(_handleServerDetectionConfigChanged);

    requestServerCheck();
  }

  Future<void> stop() async {
    _isStarted = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _orchestrator.stopRealtimeListener();

    final pendingEventsSubscription = _pendingEventsSubscription;
    final wifiConnectionSubscription = _wifiConnectionSubscription;
    final serverDetectionSubscription = _serverDetectionSubscription;
    _pendingEventsSubscription = null;
    _wifiConnectionSubscription = null;
    _serverDetectionSubscription = null;
    await pendingEventsSubscription?.cancel();
    await wifiConnectionSubscription?.cancel();
    await serverDetectionSubscription?.cancel();
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
    if (_requiresWifiForDetection && _isWifiConnected == false) {
      _handleWifiUnavailable();
      return;
    }

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
    if (!await _canAttemptServerCheck()) return;

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
    if (_requiresWifiForDetection && _isWifiConnected == false) {
      _handleWifiUnavailable();
      return;
    }

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

    if (_requiresWifiForDetection && _isWifiConnected == false) {
      _handleWifiUnavailable();
      return;
    }

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

  bool get _requiresWifiForDetection {
    return _serverDetectionConfig.requireWifiForServerDetection;
  }

  Future<bool> _canAttemptServerCheck() async {
    if (!_requiresWifiForDetection) return true;

    try {
      final isWifiConnected = await _wifiConnectivity.isWifiConnected();
      _isWifiConnected = isWifiConnected;
      if (isWifiConnected) return true;

      _handleWifiUnavailable();
      return false;
    } catch (error) {
      _handleWifiUnavailable(message: 'No se pudo comprobar WiFi: $error');
      return false;
    }
  }

  void _handleWifiConnectionChanged(bool isWifiConnected) {
    _isWifiConnected = isWifiConnected;
    if (!_isStarted || !_requiresWifiForDetection) return;

    if (isWifiConnected) {
      requestServerCheck();
      return;
    }

    _handleWifiUnavailable();
  }

  void _handleServerDetectionConfigChanged(bool requireWifiForDetection) {
    if (!_isStarted) return;

    if (!requireWifiForDetection) {
      requestServerCheck();
      return;
    }

    unawaited(_checkWifiGateAfterConfigChange());
  }

  Future<void> _checkWifiGateAfterConfigChange() async {
    if (await _canAttemptServerCheck()) {
      requestServerCheck();
    }
  }

  void _handleWifiUnavailable({String message = 'WiFi no disponible.'}) {
    _resetBackoff();
    _orchestrator.stopRealtimeListener();
    _publish(
      SyncAvailabilitySnapshot(
        status: SyncAvailabilityStatus.unavailable,
        message: message,
      ),
    );
  }

  void _publish(SyncAvailabilitySnapshot snapshot) {
    _snapshot = snapshot;
    if (!_snapshots.isClosed) {
      _snapshots.add(snapshot);
    }
  }
}
