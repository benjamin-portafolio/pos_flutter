import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Código de barras de una variante, almacenado como texto.
///
/// Se normaliza a NFKC porque los lectores y teclados pueden entregar dígitos
/// de ancho completo. Se conserva como `String` y nunca como `int`: un tipo
/// numérico destruiría los ceros a la izquierda de UPC-A (`012345678905`) y no
/// podría representar GS1-128.
class CodigoBarras {
  const CodigoBarras._(this.value);

  /// Longitud máxima admitida, alineada con el `varchar(32)` del servidor.
  static const maxLength = 32;

  static final RegExp _digitsOnly = RegExp(r'^[0-9]{1,32}$');

  /// Normaliza la entrada capturada. Vacío, espacios o null significan que la
  /// variante no tiene código de barras.
  factory CodigoBarras.fromInput(String? input) {
    final normalized = unorm.nfkc(input ?? '').trim();
    if (normalized.isEmpty) {
      return const CodigoBarras._(null);
    }
    if (!_digitsOnly.hasMatch(normalized)) {
      throw ArgumentError.value(
        input,
        'codigoBarras',
        'Solo admite dígitos, hasta $maxLength caracteres.',
      );
    }
    return CodigoBarras._(normalized);
  }

  final String? value;
}
