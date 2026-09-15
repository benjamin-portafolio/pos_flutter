class AgregarProductoBorradorCommand {
  const AgregarProductoBorradorCommand({
    required this.variantId,
    this.measuredQuantity,
    this.expectedUnitId,
  });
  final String variantId;

  /// Texto capturado en la unidad visible, convertido exactamente en el servicio.
  final String? measuredQuantity;

  /// Evita interpretar la cantidad si cambió la unidad mientras el diálogo estaba abierto.
  final String? expectedUnitId;
}
