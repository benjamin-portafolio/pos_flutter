import '../ventas/adjusted_sale.dart';

abstract interface class SaleAdjustmentRepository {
  Stream<List<AdjustedSale>> watchSales();
}
