enum ScaleUnit { kg }

/// Exact decimal from the wire. Never passes through floating point.
class ScaleWeight {
  const ScaleWeight({
    required this.coefficient,
    required this.decimalPlaces,
    required this.unit,
    required this.grams,
  });

  final BigInt coefficient;
  final int decimalPlaces;
  final ScaleUnit unit;
  final int grams;
}
