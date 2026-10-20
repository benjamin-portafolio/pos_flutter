import 'scale_failure.dart';
import 'scale_measurement.dart';

enum ScaleSessionState { connecting, waiting, reading, error, closing, closed }

class ScaleSessionSnapshot {
  const ScaleSessionSnapshot({
    required this.sessionId,
    required this.state,
    this.sequence = 0,
    this.receivedAt,
    this.measurement,
    this.failure,
  });

  final int sessionId;
  final ScaleSessionState state;
  final int sequence;
  final Duration? receivedAt;
  final ScaleMeasurement? measurement;
  final ScaleFailure? failure;

  bool get hasUsableWeight =>
      state == ScaleSessionState.reading &&
      failure == null &&
      measurement?.isValid == true;
}
