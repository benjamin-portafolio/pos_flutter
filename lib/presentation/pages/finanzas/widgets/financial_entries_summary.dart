import 'package:flutter/material.dart';

import '../../../../domain/finanzas/financial_report.dart';
import '../../informes/models/report_money.dart';

/// Resumen de los totales de **registros adicionales** del período (contrato
/// §2.7). `netMinor` se etiqueta «Neto de registros adicionales»; nunca
/// utilidad ni saldo de caja.
class FinancialEntriesSummaryCard extends StatelessWidget {
  const FinancialEntriesSummaryCard({super.key, required this.report});

  final FinancialReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Total(
                    label: 'Ingresos',
                    value: ReportMoney.money(report.incomeMinor),
                    color: Colors.green.shade700,
                  ),
                ),
                Expanded(
                  child: _Total(
                    label: 'Gastos',
                    value: ReportMoney.money(report.expenseMinor),
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Total(
                    label: 'Efectivo',
                    value: ReportMoney.money(report.cashMinor),
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Expanded(
                  child: _Total(
                    label: 'Transferencia',
                    value: ReportMoney.money(report.transferMinor),
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _Total(
              label: 'Neto de registros adicionales',
              value: ReportMoney.signedMoney(report.netMinor),
              color: report.netMinor.isNegative
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              destacado: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Estos totales son de registros adicionales. No son utilidad ni '
              'saldo de caja.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.value,
    required this.color,
    this.destacado = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: destacado
              ? theme.textTheme.titleSmall
              : theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: (destacado
                  ? theme.textTheme.titleLarge
                  : theme.textTheme.titleMedium)
              ?.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}