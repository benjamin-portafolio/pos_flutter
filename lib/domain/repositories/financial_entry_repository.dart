import '../finanzas/financial_report.dart';

/// Consultas de registros financieros adicionales para la UI (contrato §8.1).
abstract interface class FinancialEntryRepository {
  /// Informe del intervalo `[fromMs, toMs)` sobre `occurred_at_ms`, con
  /// totales `BigInt` y orden `occurred_at_ms DESC, id`. Incluye registros
  /// aplicados localmente con cualquier `delivery_status` (pendientes e
  /// incidencias visibles). Filtros opcionales: `method` (`cash`|`transfer`),
  /// `direction` (`in`|`out`) y `categoryId` (detalle por categoría).
  Stream<FinancialReport> watchFinancialReport({
    required int fromMs,
    required int toMs,
    String? method,
    String? direction,
    String? categoryId,
  });
}