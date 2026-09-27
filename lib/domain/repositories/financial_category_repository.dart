import '../finanzas/financial_category.dart';

/// Consultas de categorías financieras para la UI (contrato §8.1). Los
/// widgets no tocan Drift; consumen solo este puerto.
abstract interface class FinancialCategoryRepository {
  /// Categorías visibles ordenadas por `(name, id)` ascendente, byte-wise.
  Stream<List<FinancialCategory>> watchCategories();
}