import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/cuenta/saldo_cuenta_estimado.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/transfer_summary.dart';

import '../../support/fake_account_balance_baseline_repository.dart';

void main() {
  // Una foto arbitraria: 2023-11-14T22:13:20Z. Los tests juegan con los
  // instantes a uno y otro lado de este corte, nunca con fechas reales.
  const asOf = 1700000000000;

  TransferMovement mov({
    required String id,
    required int amountMinor,
    required int occurredAtMs,
    required FinancialDirection direction,
  }) => TransferMovement(
    id: id,
    eventId: 'event-$id',
    origin: TransferOrigin.financialEntry,
    method: 'transfer',
    amountMinor: amountMinor,
    occurredAtMs: occurredAtMs,
    direction: direction,
  );

  group('SaldoCuentaEstimado', () {
    test('foto mas entradas posteriores menos salidas posteriores', () {
      final resultado = SaldoCuentaEstimado.fromMovements(
        baseline: baselinePrueba(amountMinor: 25000000, asOfMs: asOf),
        movements: [
          mov(
            id: 'entrada',
            amountMinor: 100000,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.income,
          ),
          mov(
            id: 'salida',
            amountMinor: 50000,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.expense,
          ),
        ],
      );

      expect(resultado.estimatedMinor, BigInt.from(25050000));
      expect(resultado.incomeAfterAsOf, BigInt.from(100000));
      expect(resultado.expenseAfterAsOf, BigInt.from(50000));
      expect(resultado.includedCount, 2);
      expect(resultado.excludedCount, 0);
    });

    test('limite exacto: en as_of_ms queda fuera, as_of_ms + 1 queda dentro', () {
      final resultado = SaldoCuentaEstimado.fromMovements(
        baseline: baselinePrueba(amountMinor: 25000000, asOfMs: asOf),
        movements: [
          // Exactamente en el corte: el banco ya lo tenia en su saldo, sumarlo
          // seria duplicarlo (seccion 5 del plan).
          mov(
            id: 'en-el-limite',
            amountMinor: 2000,
            occurredAtMs: asOf,
            direction: FinancialDirection.income,
          ),
          mov(
            id: 'despues',
            amountMinor: 1000,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.income,
          ),
        ],
      );

      expect(
        resultado.estimatedMinor,
        BigInt.from(25001000),
        reason: 'solo el posterior al corte se suma',
      );
      expect(resultado.includedCount, 1);
      expect(resultado.excludedCount, 1);
    });

    test('anterior a as_of_ms queda fuera en silencio y no rompe el estimado', () {
      final resultado = SaldoCuentaEstimado.fromMovements(
        baseline: baselinePrueba(amountMinor: 25000000, asOfMs: asOf),
        movements: [
          mov(
            id: 'viejo',
            amountMinor: 999999,
            occurredAtMs: asOf - 1,
            direction: FinancialDirection.expense,
          ),
          mov(
            id: 'reciente',
            amountMinor: 300,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.income,
          ),
        ],
      );

      // El anterior se queda fuera: sigue siendo la foto mas lo posterior.
      expect(resultado.estimatedMinor, BigInt.from(25000300));
      expect(resultado.includedCount, 1);
      expect(resultado.excludedCount, 1);
    });

    test('saldo sobregirado: baseline negativo y egresos posteriores', () {
      final resultado = SaldoCuentaEstimado.fromMovements(
        baseline: baselinePrueba(amountMinor: -25000, asOfMs: asOf),
        movements: [
          mov(
            id: 'egreso',
            amountMinor: 300000,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.expense,
          ),
        ],
      );

      expect(resultado.estimatedMinor, BigInt.from(-325000));
    });

    test('sin movimientos el estimado es la foto y nada mas', () {
      final resultado = SaldoCuentaEstimado.fromMovements(
        baseline: baselinePrueba(amountMinor: 25000000, asOfMs: asOf),
        movements: const [],
      );

      expect(resultado.estimatedMinor, BigInt.from(25000000));
      expect(resultado.includedCount, 0);
      expect(resultado.excludedCount, 0);
    });

    test('los egresos posteriores restan aunque el flujo del periodo sea otro', () {
      final resultado = SaldoCuentaEstimado.fromMovements(
        baseline: baselinePrueba(amountMinor: 25000000, asOfMs: asOf),
        movements: [
          mov(
            id: 'entrada',
            amountMinor: 7000,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.income,
          ),
          mov(
            id: 'egreso',
            amountMinor: 12000,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.expense,
          ),
        ],
      );

      // Neto negativo despues de la foto: el estimado baja de la foto.
      expect(
        resultado.estimatedMinor,
        BigInt.from(25000000) + BigInt.from(7000) - BigInt.from(12000),
      );
    });
  });
}