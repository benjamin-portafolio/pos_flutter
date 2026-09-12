/// Datos capturados de una línea. Los cambios de catálogo no los reescriben.
class SaleItemSnapshot {
  SaleItemSnapshot({
    required this.variantId,
    required String productName,
    String? variantName,
    required this.saleMode,
    required this.quantity,
    required this.measuredQuantityAtomic,
    required this.unitPriceMinor,
    required this.standardCostMinor,
    required this.priceReferenceQuantityAtomic,
    required this.unitCode,
    required this.unitSymbol,
    required this.unitAtomicFactor,
  }) : productName = productName.trim(),
       variantName = variantName?.trim().isEmpty == true
           ? null
           : variantName?.trim() {
    if (variantId.trim().isEmpty || this.productName.isEmpty) {
      throw const FormatException(
        'El artículo y su variante son obligatorios.',
      );
    }
    _positive(unitPriceMinor);
    if (standardCostMinor != null &&
        (standardCostMinor! < 0 || standardCostMinor! > maxInteger)) {
      throw const FormatException('Costo estándar inválido.');
    }
    if (saleMode == 'unit') {
      _positive(quantity);
      if (measuredQuantityAtomic != null ||
          priceReferenceQuantityAtomic != null ||
          unitCode != null ||
          unitSymbol != null ||
          unitAtomicFactor != null) {
        throw const FormatException('Una venta por unidad no admite medidas.');
      }
    } else if (saleMode == 'measured') {
      _positive(measuredQuantityAtomic);
      _positive(priceReferenceQuantityAtomic);
      _positive(unitAtomicFactor);
      if (quantity != null ||
          unitCode == null ||
          unitCode!.trim().isEmpty ||
          unitSymbol == null ||
          unitSymbol!.trim().isEmpty) {
        throw const FormatException('La venta medida requiere su unidad.');
      }
    } else {
      throw const FormatException('Modo de venta inválido.');
    }
    totalMinor; // Valida también el rango del importe calculado.
  }

  static const maxInteger = 9007199254740991;
  final String variantId;
  final String productName;
  final String? variantName;
  final String saleMode;
  final int? quantity;
  final int? measuredQuantityAtomic;
  final int unitPriceMinor;
  final int? standardCostMinor;
  final int? priceReferenceQuantityAtomic;
  final String? unitCode;
  final String? unitSymbol;
  final int? unitAtomicFactor;

  int get totalMinor {
    final numerator =
        BigInt.from(unitPriceMinor) *
        BigInt.from(quantity ?? measuredQuantityAtomic!);
    final denominator = BigInt.from(priceReferenceQuantityAtomic ?? 1);
    final result =
        (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
    if (result > BigInt.from(maxInteger)) {
      throw const FormatException('El importe excede el límite permitido.');
    }
    return result.toInt();
  }

  bool sameConditions(SaleItemSnapshot other) =>
      variantId == other.variantId &&
      productName == other.productName &&
      variantName == other.variantName &&
      saleMode == other.saleMode &&
      unitPriceMinor == other.unitPriceMinor &&
      standardCostMinor == other.standardCostMinor &&
      priceReferenceQuantityAtomic == other.priceReferenceQuantityAtomic &&
      unitCode == other.unitCode &&
      unitSymbol == other.unitSymbol &&
      unitAtomicFactor == other.unitAtomicFactor;

  SaleItemSnapshot plus(SaleItemSnapshot other) {
    if (!sameConditions(other)) {
      throw StateError('Las condiciones de las líneas son distintas.');
    }
    return SaleItemSnapshot.fromJson({
      ...toJson(),
      'quantity': quantity == null ? null : quantity! + other.quantity!,
      'measured_quantity_atomic': measuredQuantityAtomic == null
          ? null
          : measuredQuantityAtomic! + other.measuredQuantityAtomic!,
    });
  }

  Map<String, Object?> toJson() => {
    'variant_id': variantId,
    'product_name_snapshot': productName,
    'variant_name_snapshot': variantName,
    'sale_mode_snapshot': saleMode,
    'quantity': quantity,
    'measured_quantity_atomic': measuredQuantityAtomic,
    'unit_price_minor': unitPriceMinor,
    'standard_cost_minor_snapshot': standardCostMinor,
    'price_reference_quantity_atomic_snapshot': priceReferenceQuantityAtomic,
    'sale_unit_code_snapshot': unitCode,
    'sale_unit_symbol_snapshot': unitSymbol,
    'sale_unit_atomic_factor_snapshot': unitAtomicFactor,
  };

  factory SaleItemSnapshot.fromJson(Map<String, Object?> json) {
    String? text(String key, {bool required = false}) {
      final value = json[key];
      if (value == null && !required) return null;
      if (value is! String || (required && value.trim().isEmpty)) {
        throw FormatException('Campo inválido: $key');
      }
      return value;
    }

    int? number(String key, {bool required = false}) {
      final value = json[key];
      if (value == null && !required) return null;
      if (value is! int) throw FormatException('Campo inválido: $key');
      return value;
    }

    return SaleItemSnapshot(
      variantId: text('variant_id', required: true)!,
      productName: text('product_name_snapshot', required: true)!,
      variantName: text('variant_name_snapshot'),
      saleMode: text('sale_mode_snapshot', required: true)!,
      quantity: number('quantity'),
      measuredQuantityAtomic: number('measured_quantity_atomic'),
      unitPriceMinor: number('unit_price_minor', required: true)!,
      standardCostMinor: number('standard_cost_minor_snapshot'),
      priceReferenceQuantityAtomic: number(
        'price_reference_quantity_atomic_snapshot',
      ),
      unitCode: text('sale_unit_code_snapshot'),
      unitSymbol: text('sale_unit_symbol_snapshot'),
      unitAtomicFactor: number('sale_unit_atomic_factor_snapshot'),
    );
  }

  static void _positive(int? value) {
    if (value == null || value <= 0 || value > maxInteger) {
      throw const FormatException(
        'Cantidad o precio fuera del rango permitido.',
      );
    }
  }
}
