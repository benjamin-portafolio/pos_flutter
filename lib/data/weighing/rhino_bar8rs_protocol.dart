import '../../application/weighing/scale_failure.dart';
import '../../application/weighing/scale_measurement.dart';
import '../../application/weighing/scale_weight.dart';

/// CR-delimited ASCII verified on the connected BAR-8RS (2026-10-20).
/// No inferred stability flags, implicit units, prices or control commands.
class RhinoBar8RsProtocol {
  static const weightRequest = <int>[0x50]; // Manufacturer's read-only 'P'.
  static const maxFrameBytes = 64;
  static final _frame = RegExp(r'^ *([+-]?[0-9]+)\.([0-9]+) ([A-Za-z]+)$');
  static final _maxGrams = BigInt.from(9007199254740991);
  final _buffer = <int>[];
  bool _discarding = false;
  bool _afterCr = false;

  int get bufferedBytes => _buffer.length;

  void reset() {
    _buffer.clear();
    _discarding = false;
    _afterCr = false;
  }

  List<ScaleMeasurement> add(List<int> bytes) {
    final result = <ScaleMeasurement>[];
    for (final byte in bytes) {
      if (byte == 10 && _afterCr) {
        _afterCr = false;
        continue;
      }
      _afterCr = byte == 13;
      if (byte == 13) {
        if (_discarding) {
          _discarding = false;
        } else {
          result.add(_parse(String.fromCharCodes(_buffer)));
        }
        _buffer.clear();
      } else if (!_discarding) {
        if (byte < 32 || byte > 126 || _buffer.length == maxFrameBytes) {
          // Report immediately, then discard the WHOLE damaged frame. Never
          // reinterpret a valid-looking suffix after a noisy/oversized prefix.
          result.add(
            const ScaleMeasurement(failure: ScaleFailure.invalidFrame),
          );
          _buffer.clear();
          _discarding = true;
        } else {
          _buffer.add(byte);
        }
      }
    }
    return result;
  }

  ScaleMeasurement _parse(String frame) {
    final match = _frame.firstMatch(frame);
    if (match == null) {
      return const ScaleMeasurement(failure: ScaleFailure.invalidFrame);
    }
    // Only kg was physically verified. 'g', lb and absent units are rejected
    // until an explicit protocol extension has its own physical evidence.
    if (match[3] != 'kg') {
      return const ScaleMeasurement(failure: ScaleFailure.unsupportedUnit);
    }
    final fraction = match[2]!;
    final coefficient = BigInt.parse('${match[1]}$fraction');
    final divisor = BigInt.from(10).pow(fraction.length);
    final numerator = coefficient * BigInt.from(1000);
    if (numerator.remainder(divisor) != BigInt.zero) {
      return const ScaleMeasurement(
        failure: ScaleFailure.unrepresentableWeight,
      );
    }
    final grams = numerator ~/ divisor;
    if (grams.abs() > _maxGrams) {
      return const ScaleMeasurement(failure: ScaleFailure.overflow);
    }
    return ScaleMeasurement(
      weight: ScaleWeight(
        coefficient: coefficient,
        decimalPlaces: fraction.length,
        unit: ScaleUnit.kg,
        grams: grams.toInt(),
      ),
      failure: grams <= BigInt.zero ? ScaleFailure.nonPositive : null,
    );
  }
}
