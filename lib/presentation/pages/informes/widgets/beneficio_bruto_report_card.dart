import 'package:flutter/material.dart';
import '../models/beneficio_bruto_report.dart';

class BeneficioBrutoReportCard extends StatelessWidget {
  const BeneficioBrutoReportCard({required this.report, super.key});
  final BeneficioBrutoReport report;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (report.estado == BeneficioBrutoEstado.noDisponible) {
      return _GrossCard(
        title: report.titulo,
        child: const Text(
          'Las líneas de este período no registran el costo estándar.',
        ),
      );
    }
    final negative = report.profitMinor.isNegative;
    return _GrossCard(
      title: report.titulo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.monto!,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: negative
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          if (report.detalleSinCosto != null) ...[
            const SizedBox(height: 4),
            Text(report.detalleSinCosto!),
          ],
          const SizedBox(height: 8),
          Text(
            'Calculado con el costo estándar registrado en la venta.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _GrossCard extends StatelessWidget {
  const _GrossCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
