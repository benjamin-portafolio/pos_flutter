enum DimensionUnidad {
  count('count', 'Conteo'),
  mass('mass', 'Masa'),
  volume('volume', 'Volumen');

  const DimensionUnidad(this.code, this.label);

  final String code;
  final String label;

  static DimensionUnidad fromCode(String code) => switch (code) {
    'count' => DimensionUnidad.count,
    'mass' => DimensionUnidad.mass,
    'volume' => DimensionUnidad.volume,
    _ => throw ArgumentError.value(code, 'code', 'Dimensión desconocida.'),
  };
}
