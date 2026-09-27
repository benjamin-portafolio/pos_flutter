import '../models/sync_event.dart';
import 'financial_category_projection.dart';

/// Puerta de la proyección local de categorías financieras. Provee además la
/// transacción atómica y la lectura del evento de creación por id, para que el
/// command service haga idempotencia y persistencia en una sola unidad de
/// trabajo (patrón `CreditoCommandService.registrarAbono`).
abstract interface class FinancialCategoryProjectionStore {
  Future<T> atomic<T>(Future<T> Function() action);

  Future<FinancialCategoryProjection?> findById(String id);

  /// Evento de creación de la categoría existente con `id`, o `null` si no
  /// existe categoría local con esa identidad.
  Future<SyncEvent?> categoryEvent(String id);

  Future<void> insert(FinancialCategoryProjection projection);

  Future<void> advanceServerSequence(String id, int serverSequence);
}