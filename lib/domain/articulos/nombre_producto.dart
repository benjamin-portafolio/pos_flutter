import 'package:unorm_dart/unorm_dart.dart' as unorm;

class NombreProducto {
  const NombreProducto._(this.value);

  factory NombreProducto.fromInput(String input) {
    final normalized = unorm.nfkc(input).trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(input, 'nombre', 'Debe tener contenido.');
    }
    if (normalized.runes.length > 160) {
      throw ArgumentError.value(
        input,
        'nombre',
        'No puede exceder 160 caracteres.',
      );
    }
    return NombreProducto._(normalized);
  }

  final String value;
}
