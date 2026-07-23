class NombreCategoria {
  const NombreCategoria._(this.value);

  factory NombreCategoria.fromInput(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(input, 'nombre', 'Debe tener contenido.');
    }
    return NombreCategoria._(normalized);
  }

  final String value;
}
