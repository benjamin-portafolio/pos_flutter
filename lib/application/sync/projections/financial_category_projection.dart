import 'sync_projection.dart';

/// Proyección local de una categoría financiera (`financial_categories`).
/// `direction`/`nature` se conservan como códigos string para comparar contra
/// payloads y filas Drift sin acoplar a la capa de datos.
class FinancialCategoryProjection extends SyncProjection {
  const FinancialCategoryProjection({
    required super.id,
    required this.name,
    required this.direction,
    required this.nature,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String name;
  final String direction;
  final String nature;
}