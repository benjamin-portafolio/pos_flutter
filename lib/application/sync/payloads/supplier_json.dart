/// Validación compartida por los contratos de proveedor y sus relaciones.
abstract final class SupplierJson {
  static const maxSafeInteger = 9007199254740991;

  static String requiredText(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field debe ser texto no vacío.');
    }
    return value.trim();
  }

  static String? optionalText(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$field debe ser texto o null.');
    }
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String uuid(Object? value, String field) {
    final text = requiredText(value, field);
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(text)) {
      throw FormatException('$field debe ser un UUID v4.');
    }
    return text.toLowerCase();
  }

  static int integer(Object? value, String field, {int min = 0}) {
    if (value is! int || value < min || value > maxSafeInteger) {
      throw FormatException(
        '$field debe ser entero entre $min y $maxSafeInteger.',
      );
    }
    return value;
  }

  static Map<String, Object?> object(Object? value, String field) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw FormatException('$field debe ser un objeto JSON.');
    }
    return Map<String, Object?>.from(value);
  }
}
