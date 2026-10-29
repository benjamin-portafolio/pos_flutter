import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/category_sales_group.dart';
import '../models/report_money.dart';

/// Dona para importes positivos; los negativos se conservan en la lista.
class CategorySalesChart extends StatelessWidget {
  const CategorySalesChart({
    required this.groups,
    required this.onTap,
    super.key,
  });
  final List<CategorySalesGroup> groups;
  final ValueChanged<CategorySalesGroup> onTap;

  @override
  Widget build(BuildContext context) {
    final positive = groups.where((g) => g.totalMinor > BigInt.zero).toList();
    final total = positive.fold(BigInt.zero, (n, g) => n + g.totalMinor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (positive.isNotEmpty)
              SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  painter: _DonutPainter(
                    fractions: [
                      for (final g in positive)
                        ReportMoney.percentOf(g.totalMinor, total) / 100,
                    ],
                  ),
                ),
              ),
            if (groups.any((g) => g.totalMinor.isNegative))
              const Text(
                'La gráfica representa solo importes positivos; la lista incluye los negativos.',
              ),
            for (var i = 0; i < groups.length; i++)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.circle,
                  color: groups[i].totalMinor.isNegative
                      ? Theme.of(context).colorScheme.error
                      : Colors.primaries[(positive
                                .indexOf(groups[i])
                                .clamp(0, positive.length)) %
                            Colors.primaries.length],
                ),
                title: Text(groups[i].label),
                subtitle: Text(ReportMoney.signedMoney(groups[i].totalMinor)),
                onTap: () => onTap(groups[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.fractions});
  final List<double> fractions;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var angle = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      final sweep = fractions[i] * math.pi * 2;
      canvas.drawArc(
        rect.deflate(22),
        angle,
        sweep,
        false,
        Paint()
          ..color = Colors.primaries[i % Colors.primaries.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 32,
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}
