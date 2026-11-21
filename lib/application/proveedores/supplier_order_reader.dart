import 'supplier_order_detail.dart';

abstract interface class SupplierOrderReader {
  Future<SupplierOrderDetail?> readDetail(String id);
  Stream<SupplierOrderDetail?> watchDetail(String id);
}
