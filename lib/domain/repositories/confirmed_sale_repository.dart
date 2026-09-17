import '../ventas/confirmed_sale.dart';

abstract interface class ConfirmedSaleRepository {
  Stream<List<ConfirmedSale>> watchSales();
}
