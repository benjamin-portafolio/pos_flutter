/// Lista cerrada para impedir copias monetarias ocultas en eventos quotation.
class QuotationJson {
  static const maxInteger = 9007199254740991;
  static void keys(Map<String, Object?> json, Set<String> keys) {
    if (json.length != keys.length || !keys.containsAll(json.keys)) {
      throw const FormatException('Campos de cotización incompatibles.');
    }
  }

  static String? text(
    Map<String, Object?> json,
    String key, {
    bool nullable = false,
  }) {
    final value = json[key];
    if (nullable && value == null) return null;
    if (value is! String) throw FormatException('Texto inválido: $key');
    return value;
  }

  static int? number(
    Map<String, Object?> json,
    String key, {
    bool nullable = false,
  }) {
    final value = json[key];
    if (nullable && value == null) return null;
    if (value is! int) throw FormatException('Entero inválido: $key');
    return value;
  }

  static void positive(int? value) {
    if (value == null || value <= 0 || value > maxInteger) {
      throw const FormatException('Cantidad fuera de rango.');
    }
  }

  static void date(int value) {
    positive(value);
    if (value % 1000 != 0) throw const FormatException('Fecha inválida.');
  }

  static List<Map<String, Object?>> lines(Object? value) {
    if (value is! List || value.any((line) => line is! Map<String, Object?>)) {
      throw const FormatException('Líneas inválidas.');
    }
    return value.cast<Map<String, Object?>>();
  }
}
