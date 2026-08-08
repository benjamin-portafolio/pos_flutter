class VarianteListado {
  const VarianteListado({
    required this.varianteId,
    required this.nombre,
    required this.precioVentaMenor,
    required this.predeterminada,
    required this.orden,
  });

  final String varianteId;
  final String? nombre;
  final int precioVentaMenor;
  final bool predeterminada;
  final int orden;
}
