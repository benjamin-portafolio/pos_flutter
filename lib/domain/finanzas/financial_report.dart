import 'financial_direction.dart';
import 'financial_entry.dart';

/// Informe de registros adicionales para la UI (contrato §8.1). Totales con
/// `BigInt`; el intervalo y la composición de `entries` ya vienen filtrados por
/// el repositorio. `netMinor` es «Neto de registros adicionales», nunca
/// utilidad ni saldo de caja.
class FinancialReport {
  const FinancialReport({
    required this.entries,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.cashMinor,
    required this.transferMinor,
    required this.netMinor,
  });

  factory FinancialReport.fromEntries(List<FinancialEntry> entries) {
    var income = BigInt.zero;
    var expense = BigInt.zero;
    var cash = BigInt.zero;
    var transfer = BigInt.zero;
    for (final entry in entries) {
      final amount = BigInt.from(entry.amountMinor);
      if (entry.direction == FinancialDirection.income) {
        income += amount;
      } else {
        expense += amount;
      }
      if (entry.method == 'cash') {
        cash += amount;
      } else {
        transfer += amount;
      }
    }
    return FinancialReport(
      entries: List.unmodifiable(entries),
      incomeMinor: income,
      expenseMinor: expense,
      cashMinor: cash,
      transferMinor: transfer,
      netMinor: income - expense,
    );
  }

  final List<FinancialEntry> entries;
  final BigInt incomeMinor;
  final BigInt expenseMinor;
  final BigInt cashMinor;
  final BigInt transferMinor;

  /// Ingresos menos gastos del intervalo (puede ser negativo; BigInt).
  final BigInt netMinor;
}