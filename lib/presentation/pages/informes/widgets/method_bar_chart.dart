import 'package:flutter/material.dart';

import '../models/report_money.dart';
import '../models/ventas_por_metodo_report.dart';

/// Gráfica de barras del desglose de ventas por método.
///
/// Barras proporcionales al importe de cada categoría sobre el mayor del
/// período, con etiqueta, importe y porcentaje. Se dibuja con widgets de
/// Flutter para no agregar dependencias y conserva el estilo del proyecto.
class MethodBarChart extends StatelessWidget {
  const MethodBarChart({
    required this.categories,
    required this.total,
    super.key,
  });

  final List<VentasPorMetodoCategoria> categories;
  final BigInt total;

  @override
  Widget build(BuildContext context) {
    final max = categories.fold<BigInt>(
      BigInt.zero,
      (current, category) =>
          category.amountMinor > current ? category.amountMinor : current,
    );
    return Semantics(
      label:
          'Gráfica de ventas por método. ${categories.map(
            (c) => '${c.label}: ${ReportMoney.money(c.amountMinor)}, '
                '${ReportMoney.percentOf(c.amountMinor, total).toStringAsFixed(1)}% del total.',
          ).join(' ')}',
      child: SizedBox(
        height: 200,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < categories.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _MethodBar(category: categories[i], max: max, total: total),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MethodBar extends StatelessWidget {
  const _MethodBar({
    required this.category,
    required this.max,
    required this.total,
  });
  final VentasPorMetodoCategoria category;
  final BigInt max;
  final BigInt total;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = max == BigInt.zero
        ? 0.0
        : (BigInt.from(1000) * category.amountMinor) ~/ max / BigInt.from(1000);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: ratio,
              widthFactor: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  color: _MethodColor.of(category.metodo, theme),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            ReportMoney.money(category.amountMinor),
            style: theme.textTheme.bodySmall,
            maxLines: 1,
          ),
        ),
        Text(
          category.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium,
        ),
        Text(
          '${ReportMoney.percentOf(category.amountMinor, total).toStringAsFixed(1)}%',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Colores por método derivados del tema para mantener consistencia visual.
abstract final class _MethodColor {
  static Color of(MetodoVenta metodo, ThemeData theme) => switch (metodo) {
    MetodoVenta.efectivo => theme.colorScheme.primary,
    MetodoVenta.transferencia => theme.colorScheme.secondary,
    MetodoVenta.credito => theme.colorScheme.tertiary,
    MetodoVenta.otros => Colors.blueGrey.shade400,
  };
}