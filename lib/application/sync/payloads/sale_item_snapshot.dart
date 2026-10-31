import '../../../domain/ventas/effective_sale_price.dart';
import '../../../domain/ventas/measured_sale_calculator.dart';
import 'inventory_movement_payload.dart';

/// Datos capturados de una línea. Los cambios de catálogo no los reescriben.
class SaleItemSnapshot {
  SaleItemSnapshot({
    this.priceSnapshotVersion,
    this.normalPriceMinorSnapshot,
    this.offerPriceMinorSnapshot,
    this.effectivePriceSource,
    this.priceSelection,
    this.priceConfigurationEventId,
    required this.variantId,
    this.consumptionConfigurationKey,
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
    if (priceSnapshotVersion != null) {
      if (priceSnapshotVersion != 2 ||
          priceSelection != 'inherit' ||
          !['normal', 'offer'].contains(effectivePriceSource)) {
        throw const FormatException('Snapshot v2 incompleto.');
      }
      _positive(normalPriceMinorSnapshot);
      if (offerPriceMinorSnapshot != null) {
        _positive(offerPriceMinorSnapshot);
        if (offerPriceMinorSnapshot! > normalPriceMinorSnapshot!) {
          throw const FormatException('Oferta mayor al normal.');
        }
      }
      InventoryMovementPayload.requiredUuidV4(
        priceConfigurationEventId ?? '',
        'price_configuration_event_id',
      );
      if (unitPriceMinor !=
          (effectivePriceSource == 'offer'
              ? offerPriceMinorSnapshot
              : normalPriceMinorSnapshot)) {
        throw const FormatException('Precio efectivo incoherente.');
      }
    } else if ([
      normalPriceMinorSnapshot,
      offerPriceMinorSnapshot,
      effectivePriceSource,
      priceSelection,
      priceConfigurationEventId,
    ].any((v) => v != null)) {
      throw const FormatException('Snapshot parcial sin versión.');
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

  static const maxInteger = MeasuredSaleCalculator.maxInteger;
  final int? priceSnapshotVersion;
  final int? normalPriceMinorSnapshot;
  final int? offerPriceMinorSnapshot;
  final String? effectivePriceSource;
  final String? priceSelection;
  final String? priceConfigurationEventId;
  final String variantId;
  final String? consumptionConfigurationKey;
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
    if (saleMode == 'measured') {
      return const MeasuredSaleCalculator().totalMinor(
        unitPriceMinor: unitPriceMinor,
        quantityAtomic: measuredQuantityAtomic!,
        priceReferenceQuantityAtomic: priceReferenceQuantityAtomic!,
      );
    }
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

  SaleItemSnapshot withPricingMode(String mode) {
    if (!['normal', 'offer'].contains(mode) || priceSnapshotVersion != 2) {
      throw StateError(
        'Recaptura las líneas legadas o termina con sus precios originales.',
      );
    }
    final price = EffectiveSalePrice.resolve(
      mode: mode,
      normal: normalPriceMinorSnapshot!,
      offer: offerPriceMinorSnapshot,
    );
    return SaleItemSnapshot.fromJson({
      ...toJson(),
      'effective_price_source': price.source,
      'unit_price_minor': price.amount,
    });
  }

  bool sameConditions(SaleItemSnapshot other) =>
      variantId == other.variantId &&
      priceSnapshotVersion == other.priceSnapshotVersion &&
      normalPriceMinorSnapshot == other.normalPriceMinorSnapshot &&
      offerPriceMinorSnapshot == other.offerPriceMinorSnapshot &&
      effectivePriceSource == other.effectivePriceSource &&
      priceSelection == other.priceSelection &&
      priceConfigurationEventId == other.priceConfigurationEventId &&
      consumptionConfigurationKey == other.consumptionConfigurationKey &&
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

  /// Copia sin condiciones, con una cantidad absoluta corregida según el modo.
  /// Usado por la edición del borrador para conservar precio y unidad capturados.
  SaleItemSnapshot withQuantity({int? pieces, int? atomic}) {
    if (saleMode == 'unit') {
      if (atomic != null) {
        throw const FormatException('Una venta por piezas no admite medidas.');
      }
      return SaleItemSnapshot.fromJson({...toJson(), 'quantity': pieces});
    }
    if (pieces != null) {
      throw const FormatException('Una venta medida no admite piezas.');
    }
    return SaleItemSnapshot.fromJson({
      ...toJson(),
      'measured_quantity_atomic': atomic,
    });
  }

  Map<String, Object?> toJson() => {
    if (priceSnapshotVersion != null) ...{
      'price_snapshot_version': priceSnapshotVersion,
      'normal_price_minor_snapshot': normalPriceMinorSnapshot,
      'offer_price_minor_snapshot': offerPriceMinorSnapshot,
      'effective_price_source': effectivePriceSource,
      'price_selection': priceSelection,
      'price_configuration_event_id': priceConfigurationEventId,
    },
    'variant_id': variantId,
    'consumption_configuration_key': consumptionConfigurationKey,
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

    final priceKeys = [
      'price_snapshot_version',
      'normal_price_minor_snapshot',
      'offer_price_minor_snapshot',
      'effective_price_source',
      'price_selection',
      'price_configuration_event_id',
    ];
    if (priceKeys.any(json.containsKey) &&
        (!priceKeys.every(json.containsKey) ||
            json['price_snapshot_version'] != 2)) {
      throw const FormatException('Snapshot de precio parcial.');
    }
    return SaleItemSnapshot(
      priceSnapshotVersion: number('price_snapshot_version'),
      normalPriceMinorSnapshot: number('normal_price_minor_snapshot'),
      offerPriceMinorSnapshot: number('offer_price_minor_snapshot'),
      effectivePriceSource: text('effective_price_source'),
      priceSelection: text('price_selection'),
      priceConfigurationEventId: text('price_configuration_event_id'),
      variantId: text('variant_id', required: true)!,
      consumptionConfigurationKey: text('consumption_configuration_key'),
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
