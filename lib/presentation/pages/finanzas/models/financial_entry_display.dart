import '../../../../domain/finanzas/financial_entry.dart';
import '../../informes/models/report_money.dart';
import '../../informes/models/report_period.dart';

/// Formatos de presentación de un registro financiero adicional para la UI.
///
/// Solo formatea: los cálculos monetarios viven en el dominio
/// (`FinancialReport`) con `BigInt`; estos helpers no calculan ni persisten.
class FinancialEntryDisplay {
  const FinancialEntryDisplay._();

  /// Importe del registro como `$X.YY MXN`.
  static String money(FinancialEntry entry) =>
      ReportMoney.money(BigInt.from(entry.amountMinor));

  /// Etiqueta visible del método (`cash` → Efectivo, `transfer` →
  /// Transferencia). «Transfer» nunca implica saldo de un cajón.
  static String methodLabel(String method) =>
      method == 'cash' ? 'Efectivo' : 'Transferencia';

  static String directionLabel(FinancialEntry entry) => entry.direction.label;

  static String natureLabel(FinancialEntry entry) => entry.nature.label;

  /// Fecha efectiva local del registro: `26 septiembre 2026 · 12:30`.
  static String localDateTime(int occurredAtMs) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      occurredAtMs,
      isUtc: true,
    ).toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${ReportPeriod.formatDate(local)} · $hh:$mm';
  }
}