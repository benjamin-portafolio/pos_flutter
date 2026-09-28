import '../finanzas/financial_direction.dart';
import '../finanzas/transfer_summary.dart';
import 'account_balance_baseline.dart';

/// El lado bancario como STOCK: cuanto hay en la cuenta ahora.
///
/// Fase 4 conecta el saldo inicial declarado (Fase 3) con la agregacion de
/// transferencias (Fase 1). Regla exacta del corte `as_of_ms` del plan:
///
///     estimado = amount_minor del saldo inicial
///              + entradas con occurred_at_ms > as_of_ms
///              - salidas  con occurred_at_ms > as_of_ms
///
/// El operador es `>` y no `>=`: el saldo que reporta el banco en `as_of_ms`
/// ya incluye todo lo ocurrido hasta ese instante, asi que un movimiento
/// exactamente en `as_of_ms` ya esta contemplado y sumarlo seria duplicarlo.
///
/// No sustituye al flujo del periodo (`TransferSummary`): "cuanto movimos" y
/// "cuanto hay" son preguntas distintas y ambas se muestran, con etiqueta
/// distinta en cada una. Este modelo es el de "cuanto hay".
class SaldoCuentaEstimado {
  const SaldoCuentaEstimado({
    required this.baseline,
    required this.includedCount,
    required this.excludedCount,
    required this.incomeAfterAsOf,
    required this.expenseAfterAsOf,
  });

  /// Calcula el estimado desde el baseline y los movimientos de transferencia
  /// conocidos, aplicando el corte estricto `> as_of_ms`.
  ///
  /// Un movimiento capturado hoy pero con fecha anterior a `as_of_ms` queda
  /// fuera del estimado en silencio. No es un bug: el saldo declarado es una
  /// foto, y la foto ya cubre ese movimiento. [excludedCount] lo cuenta para
  /// que un desplazamiento no sea completamente invisible.
  factory SaldoCuentaEstimado.fromMovements({
    required AccountBalanceBaseline baseline,
    required List<TransferMovement> movements,
  }) {
    var income = BigInt.zero;
    var expense = BigInt.zero;
    var included = 0;
    var excluded = 0;
    for (final movement in movements) {
      if (movement.occurredAtMs > baseline.asOfMs) {
        included++;
        final amount = BigInt.from(movement.amountMinor);
        if (movement.direction == FinancialDirection.income) {
          income += amount;
        } else {
          expense += amount;
        }
      } else {
        excluded++;
      }
    }
    return SaldoCuentaEstimado(
      baseline: baseline,
      includedCount: included,
      excludedCount: excluded,
      incomeAfterAsOf: income,
      expenseAfterAsOf: expense,
    );
  }

  /// La foto: saldo que el banco reporto en `as_of_ms`.
  final AccountBalanceBaseline baseline;

  /// Movimientos posteriores a `as_of_ms`, los que si se suman.
  final int includedCount;

  /// Movimientos en `as_of_ms` o anteriores: la foto ya los cubre y quedan
  /// fuera en silencio, sin doble conteo.
  final int excludedCount;

  /// Entradas con `occurred_at_ms > as_of_ms`. Siempre `>= 0`.
  final BigInt incomeAfterAsOf;

  /// Salidas con `occurred_at_ms > as_of_ms`. Siempre `>= 0`.
  final BigInt expenseAfterAsOf;

  /// Saldo estimado en centavos: foto del banco mas lo que se movio despues.
  /// Admite negativo: la cuenta puede estar sobregirada.
  BigInt get estimatedMinor =>
      BigInt.from(baseline.amountMinor) + incomeAfterAsOf - expenseAfterAsOf;
}