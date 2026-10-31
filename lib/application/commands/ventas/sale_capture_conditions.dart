import '../../../domain/ventas/measured_sale_conditions.dart';
import '../../sync/payloads/sale_item_snapshot.dart';
import 'agregar_producto_borrador_command.dart';

/// Condiciones revisables, sin escritura. Vincula la captura a una venta/revisión.
class SaleCaptureConditions {
  const SaleCaptureConditions({
    required this.saleId,
    required this.version,
    required this.draftEventId,
    required this.pricingMode,
    required this.snapshot,
    required this.measured,
  });
  final String saleId, pricingMode;
  final String? draftEventId;
  final int version;
  final SaleItemSnapshot snapshot;
  final MeasuredSaleConditions? measured;
  AgregarProductoBorradorCommand bind(AgregarProductoBorradorCommand command) {
    if (command.variantId != snapshot.variantId) {
      throw StateError('Variante distinta.');
    }
    return AgregarProductoBorradorCommand(
      variantId: command.variantId,
      expectedSaleId: saleId,
      expectedVersion: version,
      expectedDraftEventId: draftEventId,
      expectedPricingMode: pricingMode,
      expectedPriceConfigurationEventId: snapshot.priceConfigurationEventId,
      measuredQuantity: command.measuredQuantity,
      targetAmountMinor: command.targetAmountMinor,
      expectedUnitId: command.expectedUnitId,
      expectedUnitPriceMinor: command.expectedUnitPriceMinor,
      expectedPriceReferenceQuantityAtomic:
          command.expectedPriceReferenceQuantityAtomic,
    );
  }
}
