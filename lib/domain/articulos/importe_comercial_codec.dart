import 'precio_proveedor.dart';
import 'precio_venta.dart';

/// Importes exactos de captura; no acepta redondeo ni notación exponencial.
class ImporteComercialCodec {
  const ImporteComercialCodec();

  int parse(String input, {required bool admiteCero}) {
    final text = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Ingresa un importe con hasta dos decimales.',
      );
    }
    final parts = text.split('.');
    final minor =
        BigInt.parse(parts.first) * BigInt.from(100) +
        BigInt.parse(parts.length == 1 ? '0' : parts.last.padRight(2, '0'));
    if (minor > BigInt.from(PrecioVenta.maxUnidadMenor)) {
      throw const FormatException('El importe excede el límite permitido.');
    }
    if (!admiteCero && minor == BigInt.zero) {
      throw const FormatException(
        'El precio de venta debe ser mayor que cero.',
      );
    }
    final value = minor.toInt();
    return admiteCero
        ? PrecioProveedor.fromUnidadMenor(value).unidadMenor
        : PrecioVenta.fromUnidadMenor(value).unidadMenor;
  }

  String format(int minor) =>
      '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
}
