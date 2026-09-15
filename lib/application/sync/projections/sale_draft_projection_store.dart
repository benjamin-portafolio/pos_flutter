import 'sale_item_projection.dart';
import 'sale_projection.dart';

abstract interface class SaleDraftProjectionStore {
  /// Incluye lecturas, evento y ambas proyecciones en una transacción.
  Future<T> atomic<T>(Future<T> Function() action);
  Future<SaleProjection?> findDraft(String userId, String deviceId);
  Future<SaleProjection?> findById(String id);
  Future<List<SaleItemProjection>> items(String saleId);

  /// El historial de limpieza impide restaurar un borrador eliminado.
  Future<bool> wasCleared(String saleId);

  /// Borra primero todas las líneas y luego la venta dentro de la transacción.
  Future<void> deleteDraft(String saleId);
  Future<void> saveSale(SaleProjection sale);
  Future<void> saveItem(SaleItemProjection item);
}
