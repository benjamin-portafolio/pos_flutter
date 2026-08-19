import 'package:unorm_dart/unorm_dart.dart' as unorm;

class NombreRecursoInventario {
  const NombreRecursoInventario._(this.value);

  factory NombreRecursoInventario.fromInput(String input) {
    final normalized = unorm.nfkc(input).trim();
    final length = normalized.runes.length;
    if (length < 1 || length > 160) {
      throw ArgumentError.value(
        input,
        'nombre',
        'Debe tener entre 1 y 160 caracteres.',
      );
    }
    return NombreRecursoInventario._(normalized);
  }

  final String value;
}
