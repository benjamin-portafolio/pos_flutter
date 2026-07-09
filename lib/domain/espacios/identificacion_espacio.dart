class IdentificacionEspacio {
  const IdentificacionEspacio._(this.value);

  static IdentificacionEspacio? fromOptionalInput(String? input) {
    final normalized = input?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return IdentificacionEspacio._(normalized);
  }

  final String value;
}
