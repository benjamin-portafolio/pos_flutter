import 'quotation_json.dart';
import 'sale_item_snapshot.dart';

/// Selección durable; no contiene condiciones monetarias ni de consumo.
class QuotationSelectionSnapshot {
  QuotationSelectionSnapshot({
    required String variantId,
    required String productName,
    String? variantName,
    required this.saleMode,
    required this.quantity,
    required this.measuredQuantityAtomic,
    required this.unitCode,
    required this.unitSymbol,
    required this.unitAtomicFactor,
  }) : variantId = variantId.trim(),
       productName = productName.trim(),
       variantName = variantName?.trim().isEmpty == true
           ? null
           : variantName?.trim() {
    if (this.variantId.isEmpty || this.productName.isEmpty) {
      throw const FormatException('Producto y variante requeridos.');
    }
    if (saleMode == 'unit') {
      QuotationJson.positive(quantity);
      if (measuredQuantityAtomic != null ||
          unitCode != null ||
          unitSymbol != null ||
          unitAtomicFactor != null) {
        throw const FormatException(
          'Una selección por piezas no admite medidas.',
        );
      }
    } else if (saleMode == 'measured') {
      QuotationJson.positive(measuredQuantityAtomic);
      QuotationJson.positive(unitAtomicFactor);
      if (quantity != null ||
          unitCode == null ||
          unitCode!.trim().isEmpty ||
          unitSymbol == null ||
          unitSymbol!.trim().isEmpty) {
        throw const FormatException('Una selección medida requiere unidad.');
      }
    } else {
      throw const FormatException('Modo de selección inválido.');
    }
  }
  final String variantId, productName, saleMode;
  final String? variantName, unitCode, unitSymbol;
  final int? quantity, measuredQuantityAtomic, unitAtomicFactor;
  static const fields = {
    'variant_id',
    'product_name_snapshot',
    'variant_name_snapshot',
    'sale_mode_snapshot',
    'quantity',
    'measured_quantity_atomic',
    'sale_unit_code_snapshot',
    'sale_unit_symbol_snapshot',
    'sale_unit_atomic_factor_snapshot',
  };
  factory QuotationSelectionSnapshot.fromSale(SaleItemSnapshot s) =>
      QuotationSelectionSnapshot(
        variantId: s.variantId,
        productName: s.productName,
        variantName: s.variantName,
        saleMode: s.saleMode,
        quantity: s.quantity,
        measuredQuantityAtomic: s.measuredQuantityAtomic,
        unitCode: s.unitCode,
        unitSymbol: s.unitSymbol,
        unitAtomicFactor: s.unitAtomicFactor,
      );
  Map<String, Object?> toJson() => {
    'variant_id': variantId,
    'product_name_snapshot': productName,
    'variant_name_snapshot': variantName,
    'sale_mode_snapshot': saleMode,
    'quantity': quantity,
    'measured_quantity_atomic': measuredQuantityAtomic,
    'sale_unit_code_snapshot': unitCode,
    'sale_unit_symbol_snapshot': unitSymbol,
    'sale_unit_atomic_factor_snapshot': unitAtomicFactor,
  };
  factory QuotationSelectionSnapshot.fromJson(Map<String, Object?> j) {
    QuotationJson.keys(j, fields);
    return QuotationSelectionSnapshot(
      variantId: QuotationJson.text(j, 'variant_id')!,
      productName: QuotationJson.text(j, 'product_name_snapshot')!,
      variantName: QuotationJson.text(
        j,
        'variant_name_snapshot',
        nullable: true,
      ),
      saleMode: QuotationJson.text(j, 'sale_mode_snapshot')!,
      quantity: QuotationJson.number(j, 'quantity', nullable: true),
      measuredQuantityAtomic: QuotationJson.number(
        j,
        'measured_quantity_atomic',
        nullable: true,
      ),
      unitCode: QuotationJson.text(
        j,
        'sale_unit_code_snapshot',
        nullable: true,
      ),
      unitSymbol: QuotationJson.text(
        j,
        'sale_unit_symbol_snapshot',
        nullable: true,
      ),
      unitAtomicFactor: QuotationJson.number(
        j,
        'sale_unit_atomic_factor_snapshot',
        nullable: true,
      ),
    );
  }
}
