import '../../../domain/finanzas/financial_direction.dart';
import '../../../domain/finanzas/financial_nature.dart';

/// Intención de crear una categoría financiera. `categoryId` es la identidad
/// estable de la captura: reintentar el mismo guardado reutiliza esta id.
class CrearCategoriaFinancieraCommand {
  const CrearCategoriaFinancieraCommand({
    required this.categoryId,
    required this.name,
    required this.direction,
    required this.nature,
  });

  final String categoryId;
  final String name;
  final FinancialDirection direction;
  final FinancialNature nature;
}