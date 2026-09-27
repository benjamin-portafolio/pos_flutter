import 'package:flutter/material.dart';

import '../../../domain/finanzas/financial_direction.dart';
import '../../../domain/finanzas/financial_entry.dart';
import 'models/financial_entry_display.dart';
import 'widgets/financial_delivery_status_chip.dart';

/// Detalle de un registro financiero adicional: clasificación, monto, fecha,
/// método, notas, referencia y trazabilidad/estado de entrega (contrato §8.3).
/// Una incidencia de sincronización no hace desaparecer el registro.
class FinancialEntryDetailScreen extends StatelessWidget {
  const FinancialEntryDetailScreen({super.key, required this.entry});

  final FinancialEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final income = entry.direction == FinancialDirection.income;
    final amountColor = income ? Colors.green.shade700 : Colors.red.shade700;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del registro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              FinancialEntryDisplay.money(entry),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: FinancialDeliveryStatusChip(
              status: entry.deliveryStatus,
              rejectionReason: entry.rejectionReason,
            ),
          ),
          if (entry.deliveryStatus == 'rejected' ||
              entry.deliveryStatus == 'conflict') ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                entry.rejectionReason ?? 'Incidencia de sincronización.',
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clasificación', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _DetailRow(label: 'Categoría', value: entry.categoryNameSnapshot),
                  _DetailRow(
                    label: 'Dirección',
                    value: FinancialEntryDisplay.directionLabel(entry),
                  ),
                  _DetailRow(
                    label: 'Clasificación',
                    value: FinancialEntryDisplay.natureLabel(entry),
                  ),
                  _DetailRow(label: 'Monto', value: FinancialEntryDisplay.money(entry)),
                  _DetailRow(
                    label: 'Método',
                    value: FinancialEntryDisplay.methodLabel(entry.method),
                  ),
                  _DetailRow(
                    label: 'Fecha efectiva',
                    value: FinancialEntryDisplay.localDateTime(entry.occurredAtMs),
                  ),
                  if (entry.notes != null)
                    _DetailRow(label: 'Nota', value: entry.notes!),
                  if (entry.reference != null)
                    _DetailRow(label: 'Referencia', value: entry.reference!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trazabilidad', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _DetailRow(label: 'Evento', value: entry.eventId),
                  _DetailRow(label: 'Usuario', value: entry.userId),
                  _DetailRow(label: 'Dispositivo', value: entry.deviceId),
                  _DetailRow(
                    label: 'Entrega',
                    value: _deliveryLabel(entry.deliveryStatus),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _deliveryLabel(String status) => switch (status) {
    'not_required' => 'Registro local',
    'pending' => 'Pendiente de sincronizar',
    'delivered' => 'Sincronizada',
    'rejected' || 'conflict' => 'Requiere atención',
    _ => status,
  };
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}