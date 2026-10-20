import 'dart:async';

import 'scale_exception.dart';
import 'scale_failure.dart';
import 'scale_gateway.dart';
import 'scale_profile.dart';
import 'scale_session.dart';

/// Shared across test and sale. Construction/DI never opens a serial port.
class ScaleSessionService {
  ScaleSessionService(
    this._gateway, {
    Duration Function()? now,
    this.pollInterval = const Duration(milliseconds: 250),
    this.freshness = const Duration(seconds: 2),
  }) : _now = now ?? _monotonicClock() {
    if (pollInterval <= Duration.zero || freshness <= Duration.zero) {
      throw const ScaleException(ScaleFailure.invalidConfiguration);
    }
  }

  final ScaleGateway _gateway;
  final Duration Function() _now;
  final Duration pollInterval;
  final Duration freshness;
  ScaleSession? _active;
  int _nextId = 0;
  bool _disposed = false;
  Future<void>? _configurationWork;

  static Duration Function() _monotonicClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }

  ScaleSession? get active => _active;

  ScaleSession open(ScaleProfile profile, {required ScaleSessionOwner owner}) {
    if (_disposed) throw const ScaleException(ScaleFailure.disposed);
    if (_active != null || _configurationWork != null) {
      throw const ScaleException(ScaleFailure.busy);
    }
    late final ScaleSession session;
    session = ScaleSession.internal(
      id: ++_nextId,
      owner: owner,
      profile: profile,
      gateway: _gateway,
      now: _now,
      pollInterval: pollInterval,
      freshness: freshness,
      onClosed: () {
        if (identical(_active, session)) _active = null;
      },
    );
    _active = session;
    session.start();
    return session;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _configurationWork;
    await _active?.close();
  }

  /// Reserve the idle resource across an asynchronous settings replacement.
  /// A session cannot start halfway through editing/removing its destination.
  Future<T> withIdleResource<T>(Future<T> Function() operation) async {
    if (_disposed) throw const ScaleException(ScaleFailure.disposed);
    if (_active != null || _configurationWork != null) {
      throw const ScaleException(ScaleFailure.busy);
    }
    final completed = Completer<void>();
    _configurationWork = completed.future;
    try {
      return await operation();
    } finally {
      _configurationWork = null;
      completed.complete();
    }
  }
}
