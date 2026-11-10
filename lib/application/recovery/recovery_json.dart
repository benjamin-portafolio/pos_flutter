import 'dart:convert';

/// Mismos bytes canónicos que S2: claves UTF-16 ordenadas, enteros seguros,
/// LF solo como delimitador de NDJSON, sin modificar números de payloads.
String recoveryCanonical(Object? value) {
  if (value == null || value is String || value is bool) {
    return jsonEncode(value);
  }
  if (value is int && value >= -9007199254740991 && value <= 9007199254740991) {
    return '$value';
  }
  // JSON solo tiene un tipo number: 1.0 y 1 representan el mismo entero.
  // Coincide con Number.isSafeInteger de S2, sin redondear ni admitir -0.
  if (value is double &&
      value.isFinite &&
      value.abs() <= 9007199254740991 &&
      value == value.truncateToDouble() &&
      !(value == 0 && value.isNegative)) {
    return value.toInt().toString();
  }
  if (value is List) return '[${value.map(recoveryCanonical).join(',')}]';
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${recoveryCanonical(value[k])}').join(',')}}';
  }
  throw const FormatException('JSON no canónico o entero fuera de rango.');
}

/// Convierte segundos Drift solo después de verificar el rango; multiplicar
/// primero permitiría overflow int64 y podría fabricar una fecha plausible.
String recoveryUtcFromSeconds(Object? value) {
  if (value is! int || value < -8640000000000 || value > 8640000000000) {
    throw const FormatException('Timestamp SQLite fuera de rango.');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    value * 1000,
    isUtc: true,
  ).toIso8601String();
}
