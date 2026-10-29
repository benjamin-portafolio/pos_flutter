import 'sale_adjustment_json.dart';
import 'sale_adjustment_stock.dart';

class SaleAdjustmentLine {
  SaleAdjustmentLine._(
    this.saleItemId,
    this.quantityAtomic,
    this.destination,
    this.reason,
    this.amountMinor,
    this.recoveredCostMinor,
    this.stock,
  );
  final String saleItemId;
  final int quantityAtomic;
  final String destination;
  final String? reason;
  final int amountMinor;
  final int? recoveredCostMinor;
  final List<SaleAdjustmentStock> stock;
  factory SaleAdjustmentLine.fromJson(Object? value) {
    final j = adjustmentObject(value, [
      'sale_item_id',
      'quantity_atomic',
      'destination',
      'reason',
      'amount_minor',
      'recovered_cost_minor',
      'stock',
    ]);
    return SaleAdjustmentLine._(
      adjustmentId(j['sale_item_id']),
      adjustmentInt(j['quantity_atomic'], 1),
      adjustmentChoice(j['destination'], [
        'restock',
        'not_restockable',
        'untracked',
        'void',
      ]),
      j['reason'] == null ? null : adjustmentText(j['reason']),
      adjustmentInt(j['amount_minor']),
      j['recovered_cost_minor'] == null
          ? null
          : adjustmentInt(j['recovered_cost_minor']),
      adjustmentList(j['stock'], SaleAdjustmentStock.fromJson),
    );
  }
  Map<String, Object?> toJson() => {
    'sale_item_id': saleItemId,
    'quantity_atomic': quantityAtomic,
    'destination': destination,
    'reason': reason,
    'amount_minor': amountMinor,
    'recovered_cost_minor': recoveredCostMinor,
    'stock': stock.map((v) => v.toJson()).toList(),
  };
}
