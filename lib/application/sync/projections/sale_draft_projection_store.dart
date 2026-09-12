import 'sale_projection.dart';
import 'sale_item_projection.dart';

abstract interface class SaleDraftProjectionStore {
  /// Incluye lecturas, evento y ambas proyecciones en una transacción.
  Future<T> atomic<T>(Future<T> Function() action);
  Future<SaleProjection?> findDraft(String userId, String deviceId);
  Future<SaleProjection?> findById(String id);
  Future<List<SaleItemProjection>> items(String saleId);
  Future<void> saveSale(SaleProjection sale);
  Future<void> saveItem(SaleItemProjection item);
}
