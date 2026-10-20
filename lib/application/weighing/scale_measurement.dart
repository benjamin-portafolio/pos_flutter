import 'scale_failure.dart';
import 'scale_weight.dart';

enum ScaleStability { unknown }

/// Invalid frames are observations too: they replace any previous valid weight.
class ScaleMeasurement {
  const ScaleMeasurement({this.weight, this.failure})
    : assert(weight != null || failure != null);

  final ScaleWeight? weight;
  final ScaleFailure? failure;
  // The observed BAR-8RS frame has no verified stability flag.
  ScaleStability get stability => ScaleStability.unknown;
  bool get isValid => weight != null && failure == null;
}
