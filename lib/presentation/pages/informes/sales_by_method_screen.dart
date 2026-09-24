import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import 'models/report_money.dart';
import 'models/report_period.dart';
import 'models/sales_reports_calculator.dart';
import 'models/ventas_por_metodo_report.dart';
import 'report_date_filter_screen.dart';
import 'sales_by_method_detail_screen.dart';
import 'widgets/method_bar_chart.dart';

/// Desglose de ventas confirmadas por método de pago dentro del período.
///
/// Usa `ConfirmedSale.paymentMethod` y `totalMinor`; la suma de categorías
/// coincide exactamente con la tarjeta "Ventas totales" de Informes.
class SalesByMethodScreen extends StatefulWidget {
  const SalesByMethodScreen({
    required this.initialPeriod,
    super.key,
    this.repository,
    this.now,
    this.sales,
  });

  final ReportPeriod initialPeriod;
  final ConfirmedSaleRepository? repository;
  final DateTime Function()? now;

  /// Stream opcional para compartir la lectura reactiva de Informes.
  final Stream<List<ConfirmedSale>>? sales;

  @override
  State<SalesByMethodScreen> createState() => _SalesByMethodScreenState();
}

class _SalesByMethodScreenState extends State<SalesByMethodScreen> {
  late ReportPeriod _period = widget.initialPeriod;
  late Stream<List<ConfirmedSale>> _sales =
      widget.sales ??
      (widget.repository ?? getIt<ConfirmedSaleRepository>()).watchSales();

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  Future<void> _selectPeriod() async {
    final selected = await Navigator.of(context).push<ReportPeriod>(
      MaterialPageRoute(
        builder: (_) =>
            ReportDateFilterScreen(initialPeriod: _period, today: _now()),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _period = selected);
  }

  void _openCategory(VentasPorMetodoCategoria category, ReportPeriod period) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SalesByMethodDetailScreen(
          metodo: category.metodo,
          label: category.label,
          period: period,
          repository: widget.repository,
          sales: widget.sales,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ventas por método')),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Período anterior',
                  onPressed: () => setState(() => _period = _period.shift(-1)),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _selectPeriod,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_period.label, textAlign: TextAlign.center),
                  ),
                ),
                IconButton(
                  tooltip: 'Período siguiente',
                  onPressed: () => setState(() => _period = _period.shift(1)),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),
        ),
        StreamBuilder<List<ConfirmedSale>>(
          stream: _sales,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('No se pudieron cargar las ventas.'),
                      TextButton(
                        onPressed: () => setState(
                          () => _sales =
                              widget.sales ??
                              (widget.repository ??
                                      getIt<ConfirmedSaleRepository>())
                                  .watchSales(),
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Card(
                margin: EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CircularProgressIndicator(),
                  ),
                ),
              );
            }
            return _VentasPorMetodoContent(
              period: _period,
              report: SalesReportsCalculator.ventasPorMetodo(
                _period,
                snapshot.data!,
              ),
              onOpenCategory: _openCategory,
            );
          },
        ),
      ],
    ),
  );
}

class _VentasPorMetodoContent extends StatelessWidget {
  const _VentasPorMetodoContent({
    required this.period,
    required this.report,
    required this.onOpenCategory,
  });
  final ReportPeriod period;
  final VentasPorMetodoReport report;
  final void Function(VentasPorMetodoCategoria, ReportPeriod) onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL GENERAL', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Text(
                  report.montoTotal,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (report.salesCount == 0) ...[
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Sin ventas en este período'),
          ),
          for (final categoria in report.categorias)
            _CategoriaTile(
              categoria: categoria,
              total: report.totalMinor,
              onTap: () => onOpenCategory(categoria, period),
            ),
        ] else ...[
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VENTAS POR MÉTODO', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 12),
                  MethodBarChart(
                    categories: report.categorias,
                    total: report.totalMinor,
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                for (final categoria in report.categorias)
                  _CategoriaTile(
                    categoria: categoria,
                    total: report.totalMinor,
                    onTap: () => onOpenCategory(categoria, period),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'El crédito no representa dinero recibido. '
              'Las ventas a crédito se cobran después mediante abonos.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoriaTile extends StatelessWidget {
  const _CategoriaTile({
    required this.categoria,
    required this.total,
    required this.onTap,
  });
  final VentasPorMetodoCategoria categoria;
  final BigInt total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(categoria.label),
      subtitle: Text(
        '${ReportMoney.money(categoria.amountMinor)} · '
        '${categoria.ventasCount} '
        '${categoria.ventasCount == 1 ? 'venta' : 'ventas'}',
      ),
      trailing: Text(
        '${ReportMoney.percentOf(categoria.amountMinor, total).toStringAsFixed(1)}%',
        style: theme.textTheme.titleMedium,
      ),
      onTap: onTap,
    );
  }
}