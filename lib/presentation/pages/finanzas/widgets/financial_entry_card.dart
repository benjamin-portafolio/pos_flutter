import 'package:flutter/material.dart';

import '../../../../domain/finanzas/financial_direction.dart';
import '../../../../domain/finanzas/financial_entry.dart';
import '../../informes/models/report_money.dart';
import '../financial_entry_detail_screen.dart';
import '../models/financial_entry_display.dart';
import 'financial_delivery_status_chip.dart';

/// Tarjeta de la lista reactiva de registros adicionales. Tocar abre el
/// detalle con trazabilidad y estado de entrega.
class FinancialEntryCard extends StatelessWidget {
  const FinancialEntryCard({super.key, required this.entry});

  final FinancialEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final income = entry.direction == FinancialDirection.income;
    final color = income ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          income ? Icons.arrow_upward : Icons.arrow_downward,
          color: color,
        ),
        title: Text(entry.categoryNameSnapshot),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${FinancialEntryDisplay.methodLabel(entry.method)} · '
              '${FinancialEntryDisplay.localDateTime(entry.occurredAtMs)}',
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: FinancialDeliveryStatusChip(
                status: entry.deliveryStatus,
                rejectionReason: entry.rejectionReason,
              ),
            ),
          ],
        ),
        trailing: Text(
          ReportMoney.money(BigInt.from(entry.amountMinor)),
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => FinancialEntryDetailScreen(entry: entry),
          ),
        ),
      ),
    );
  }
}