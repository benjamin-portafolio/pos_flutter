class AgregarProductoBorradorCommand {
  const AgregarProductoBorradorCommand({
    required this.variantId,
    this.measuredQuantity,
    this.targetAmountMinor,
    this.expectedUnitId,
    this.expectedUnitPriceMinor,
    this.expectedPriceReferenceQuantityAtomic,
  });
  final String variantId;

  /// Texto capturado en la unidad visible, convertido exactamente en el servicio.
  final String? measuredQuantity;

  /// Importe objetivo en centavos, alternativo a measuredQuantity.
  /// Se convierte a átomos en el servicio y no se persiste.
  final int? targetAmountMinor;

  /// Evita interpretar la cantidad si cambió la unidad mientras el diálogo estaba abierto.
  final String? expectedUnitId;

  /// Precio y referencia mostrados al capturar. Son obligatorios por importe
  /// y opcionales por cantidad; si se envía uno, se requieren ambos.
  final int? expectedUnitPriceMinor;
  final int? expectedPriceReferenceQuantityAtomic;
}
