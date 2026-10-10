import '../../../../../domain/articulos/precio_proveedor.dart';

/// Captura decimal exacta, sin separadores de miles ni conversión a double.
class ProveedorPrecioInput {
  static PrecioProveedor parse(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      throw const FormatException(
        'Captura un precio; cero debe ser explícito.',
      );
    }
    if (!RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Usa un precio no negativo con hasta dos decimales.',
      );
    }
    final parts = text.replaceAll(',', '.').split('.');
    final minor =
        BigInt.parse(parts.first) * BigInt.from(100) +
        BigInt.parse(parts.length == 1 ? '0' : parts.last.padRight(2, '0'));
    if (minor > BigInt.from(PrecioProveedor.maxUnidadMenor)) {
      throw const FormatException(
        'Precio de proveedor fuera del rango seguro.',
      );
    }
    return PrecioProveedor.fromUnidadMenor(minor.toInt());
  }

  static String format(int minor) =>
      '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
}
