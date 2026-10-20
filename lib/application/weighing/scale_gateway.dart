import 'scale_device.dart';
import 'scale_measurement.dart';
import 'scale_profile.dart';

abstract interface class ScaleGateway {
  Future<List<ScaleDevice>> listDevices();
  Future<void> open(ScaleProfile profile);

  /// One documented weight request. Must finish native I/O before completing.
  Future<List<ScaleMeasurement>> readWeight();

  /// Completes successfully only after pending I/O and the native handle close.
  /// On failure, ownership must be retained; callers may retry close.
  Future<void> close();
}
