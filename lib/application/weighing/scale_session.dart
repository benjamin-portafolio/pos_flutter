import 'dart:async';

import 'scale_exception.dart';
import 'scale_failure.dart';
import 'scale_gateway.dart';
import 'scale_profile.dart';
import 'scale_session_snapshot.dart';

enum ScaleSessionOwner { test, sale }

/// A lease returned immediately, so it can be closed while open is pending.
/// There is never more than one readWeight call in flight.
class ScaleSession {
  ScaleSession.internal({
    required this.id,
    required this.owner,
    required this.profile,
    required ScaleGateway gateway,
    required Duration Function() now,
    required this.pollInterval,
    required this.freshness,
    required void Function() onClosed,
  }) : _gateway = gateway,
       _now = now,
       _onClosed = onClosed,
       _snapshot = ScaleSessionSnapshot(
         sessionId: id,
         state: ScaleSessionState.connecting,
       );

  final int id;
  final ScaleSessionOwner owner;
  final ScaleProfile profile;
  final Duration pollInterval;
  final Duration freshness;
  final ScaleGateway _gateway;
  final Duration Function() _now;
  final void Function() _onClosed;
  final _updates = StreamController<ScaleSessionSnapshot>.broadcast();
  late Future<void> _work;
  ScaleSessionSnapshot _snapshot;
  Timer? _expiry;
  Timer? _delay;
  Completer<void>? _wake;
  Future<void>? _closingFuture;
  bool _closing = false;
  bool _closed = false;
  bool _finished = false;
  bool _started = false;
  int _sequence = 0;
  ScaleFailure? _terminalFailure;

  ScaleSessionSnapshot get snapshot => _snapshot;
  Stream<ScaleSessionSnapshot> get updates => _updates.stream;

  // Also checks the monotonic clock when queried between timer callbacks.
  bool get hasFreshWeight =>
      snapshot.hasUsableWeight &&
      snapshot.receivedAt != null &&
      _now() - snapshot.receivedAt! < freshness;

  void start() {
    if (_started) throw StateError('Scale session already started');
    _started = true;
    _work = _run();
  }

  void _publish(ScaleSessionSnapshot next) {
    _snapshot = next;
    if (!_updates.isClosed) _updates.add(next);
  }

  Future<void> _run() async {
    try {
      await _gateway.open(profile);
      if (!_closing) {
        _publish(
          ScaleSessionSnapshot(sessionId: id, state: ScaleSessionState.waiting),
        );
      }
      while (!_closing) {
        final started = _now();
        final measurements = await _gateway.readWeight();
        if (_closing) break;
        for (final measurement in measurements) {
          final received = _now();
          _expiry?.cancel();
          _publish(
            ScaleSessionSnapshot(
              sessionId: id,
              sequence: ++_sequence,
              state: ScaleSessionState.reading,
              receivedAt: received,
              measurement: measurement,
              failure: measurement.failure,
            ),
          );
          if (_closing) break;
          if (measurement.isValid) {
            final sequence = _sequence;
            _expiry = Timer(freshness, () {
              if (_closing || sequence != _sequence) return;
              _publish(
                ScaleSessionSnapshot(
                  sessionId: id,
                  sequence: sequence,
                  state: ScaleSessionState.waiting,
                  failure: ScaleFailure.stale,
                ),
              );
            });
          }
        }
        if (_closing) break;
        final remaining = pollInterval - (_now() - started);
        _wake = Completer<void>();
        _delay = Timer(remaining.isNegative ? Duration.zero : remaining, () {
          if (!_wake!.isCompleted) _wake!.complete();
        });
        await _wake!.future;
        _wake = null;
      }
    } catch (error) {
      if (!_closing) {
        _terminalFailure = error is ScaleException
            ? error.failure
            : ScaleFailure.transportError;
        _publish(
          ScaleSessionSnapshot(
            sessionId: id,
            state: ScaleSessionState.error,
            failure: _terminalFailure,
          ),
        );
      }
    } finally {
      _closing = true;
      _expiry?.cancel();
      _delay?.cancel();
      await _attemptClose();
      _finished = true;
    }
  }

  Future<void> _attemptClose() async {
    try {
      await _gateway.close();
      _closed = true;
      _publish(
        ScaleSessionSnapshot(
          sessionId: id,
          state: ScaleSessionState.closed,
          failure: _terminalFailure,
        ),
      );
      _onClosed();
      unawaited(_updates.close());
    } catch (_) {
      _publish(
        ScaleSessionSnapshot(
          sessionId: id,
          state: ScaleSessionState.error,
          failure: ScaleFailure.closeFailed,
        ),
      );
    }
  }

  Future<void> close() {
    if (_closed) return Future.value();
    return _closingFuture ??= _close().whenComplete(
      () => _closingFuture = null,
    );
  }

  Future<void> _close() async {
    _closing = true;
    _expiry?.cancel();
    _delay?.cancel();
    _publish(
      ScaleSessionSnapshot(sessionId: id, state: ScaleSessionState.closing),
    );
    if (_wake != null && !_wake!.isCompleted) _wake!.complete();
    if (_finished) {
      await _attemptClose();
    } else {
      await _work;
    }
    if (!_closed) throw const ScaleException(ScaleFailure.closeFailed);
  }
}
