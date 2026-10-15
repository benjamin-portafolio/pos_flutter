import '../../../application/commands/ventas/agregar_producto_borrador_command.dart';

/// Intención temporal del formulario; el importe objetivo no se persiste.
class SaleQuantityFormResult {
  const SaleQuantityFormResult({
    required this.measuredQuantity,
    required this.targetAmountMinor,
    required this.expectedUnitId,
    required this.expectedUnitPriceMinor,
    required this.expectedPriceReferenceQuantityAtomic,
    required this.displayQuantity,
    required this.displayUnitSymbol,
  });

  final String? measuredQuantity;
  final int? targetAmountMinor;
  final String expectedUnitId;
  final int expectedUnitPriceMinor;
  final int expectedPriceReferenceQuantityAtomic;

  /// Cantidad revisada, para el mensaje del lector; no sustituye la intención.
  final String displayQuantity;
  final String displayUnitSymbol;

  AgregarProductoBorradorCommand toCommand(String variantId) =>
      AgregarProductoBorradorCommand(
        variantId: variantId,
        measuredQuantity: measuredQuantity,
        targetAmountMinor: targetAmountMinor,
        expectedUnitId: expectedUnitId,
        expectedUnitPriceMinor: expectedUnitPriceMinor,
        expectedPriceReferenceQuantityAtomic:
            expectedPriceReferenceQuantityAtomic,
      );
}
