import 'sale_mode.dart';

sealed class SaleConfiguration {
  const SaleConfiguration();

  SaleMode get mode;
  String? get saleUnitId;
  int? get priceReferenceQuantityAtomic;
}

final class UnitSaleConfiguration extends SaleConfiguration {
  const UnitSaleConfiguration();

  @override
  SaleMode get mode => SaleMode.unit;

  @override
  String? get saleUnitId => null;

  @override
  int? get priceReferenceQuantityAtomic => null;

  @override
  bool operator ==(Object other) => other is UnitSaleConfiguration;

  @override
  int get hashCode => SaleMode.unit.hashCode;
}

final class MeasuredSaleConfiguration extends SaleConfiguration {
  factory MeasuredSaleConfiguration({
    required String saleUnitId,
    required int priceReferenceQuantityAtomic,
  }) {
    final normalizedUnitId = saleUnitId.trim();
    if (normalizedUnitId.isEmpty) {
      throw ArgumentError.value(
        saleUnitId,
        'saleUnitId',
        'La unidad de venta es obligatoria.',
      );
    }
    if (priceReferenceQuantityAtomic <= 0) {
      throw ArgumentError.value(
        priceReferenceQuantityAtomic,
        'priceReferenceQuantityAtomic',
        'La cantidad de referencia debe ser positiva.',
      );
    }
    return MeasuredSaleConfiguration._(
      saleUnitId: normalizedUnitId,
      priceReferenceQuantityAtomic: priceReferenceQuantityAtomic,
    );
  }

  const MeasuredSaleConfiguration._({
    required this.saleUnitId,
    required this.priceReferenceQuantityAtomic,
  });

  @override
  SaleMode get mode => SaleMode.measured;

  @override
  final String saleUnitId;

  @override
  final int priceReferenceQuantityAtomic;

  @override
  bool operator ==(Object other) =>
      other is MeasuredSaleConfiguration &&
      other.saleUnitId == saleUnitId &&
      other.priceReferenceQuantityAtomic == priceReferenceQuantityAtomic;

  @override
  int get hashCode => Object.hash(saleUnitId, priceReferenceQuantityAtomic);
}
