import 'financial_direction.dart';
import 'financial_nature.dart';

/// Categoría financiera adicional (ingreso/gasto) para la UI. Modelo de
/// consulta sin Drift; `direction`/`nature` inmutables desde el alta.
class FinancialCategory {
  const FinancialCategory({
    required this.id,
    required this.name,
    required this.direction,
    required this.nature,
  });

  final String id;
  final String name;
  final FinancialDirection direction;
  final FinancialNature nature;
}