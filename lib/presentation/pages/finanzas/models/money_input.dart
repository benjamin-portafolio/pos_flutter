/// Modelo de formulario para capturar un importe en pesos y convertirlo a
/// centavos enteros. No usa `double`: la conversión es de texto a entero
/// (`amount_minor`), conforme al contrato §2.3.
class MoneyInput {
  const MoneyInput._();

  /// Límite del contrato: `amount_minor` es un entero seguro positivo.
  static const int maxMinor = 9007199254740991;

  /// Parsea un texto de importe a centavos enteros.
  ///
  /// Acepta `1234`, `1234.5` y `1234.56` (máximo dos decimales). Devuelve
  /// `null` si el formato no es válido, el importe es cero o negativo, o
  /// excede el entero seguro del contrato.
  static int? parseMinor(String text) {
    final match = RegExp(r'^(\d{1,15})(?:\.(\d{1,2}))?$').firstMatch(
      text.trim(),
    );
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final cents = match.group(2) == null
        ? 0
        : int.parse(match.group(2)!.padRight(2, '0'));
    final minor = whole * 100 + cents;
    if (minor <= 0 || minor > maxMinor) return null;
    return minor;
  }
}