import '../../../../domain/finanzas/financial_category.dart';
import '../../../../domain/finanzas/financial_direction.dart';
import '../../../../domain/finanzas/financial_nature.dart';

/// Resultado del formulario de alta de categoría financiera. La UI lo envía al
/// command service; `categoryId` es la identidad estable de la intención.
class CategoriaFinancieraFormResult {
  const CategoriaFinancieraFormResult({
    required this.categoryId,
    required this.name,
    required this.direction,
    required this.nature,
  });

  final String categoryId;
  final String name;
  final FinancialDirection direction;
  final FinancialNature nature;

  /// Categoría de dominio para el siguiente paso del flujo (registro).
  FinancialCategory toCategory() => FinancialCategory(
    id: categoryId,
    name: name,
    direction: direction,
    nature: nature,
  );
}