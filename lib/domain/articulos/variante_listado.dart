class VarianteListado {
  const VarianteListado({
    required this.varianteId,
    required this.nombre,
    required this.precioVentaMenor,
    this.costoEstandarMenor,
    required this.predeterminada,
    required this.orden,
  });

  final String varianteId;
  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final bool predeterminada;
  final int orden;
}
