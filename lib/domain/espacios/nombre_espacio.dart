class NombreEspacio {
  const NombreEspacio._(this.value);

  factory NombreEspacio.fromInput(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(input, 'nombre', 'Debe tener contenido.');
    }
    return NombreEspacio._(normalized);
  }

  final String value;
}
