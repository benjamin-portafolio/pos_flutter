import 'package:flutter/material.dart';

import '../../../domain/articulos/articulo_listado.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import '../caja/sale_receipt_screen.dart';
import 'models/category_sales_group.dart';
import 'models/category_sales_report.dart';
import 'models/report_money.dart';
import 'models/report_period.dart';
import 'models/sales_reports_calculator.dart';
import 'report_date_filter_screen.dart';
import 'widgets/beneficio_bruto_report_card.dart';
import 'widgets/category_sales_chart.dart';

/// Categorías → variantes → aportes por ticket; lectura reactiva local.
class CategorySalesReportScreen extends StatefulWidget {
  const CategorySalesReportScreen({
    required this.initialPeriod,
    required this.repository,
    required this.productoRepository,
    this.categoryKey,
    this.productKey,
    this.title,
    this.now,
    super.key,
  });

  final ReportPeriod initialPeriod;
  final ConfirmedSaleRepository repository;
  final ProductoRepository productoRepository;
  final String? categoryKey, productKey, title;
  final DateTime Function()? now;

  @override
  State<CategorySalesReportScreen> createState() =>
      _CategorySalesReportScreenState();
}

class _CategorySalesReportScreenState extends State<CategorySalesReportScreen> {
  late ReportPeriod _period = widget.initialPeriod;
  late Stream<List<ConfirmedSale>> _sales = widget.repository.watchSales();
  late Stream<List<ArticuloListado>> _articles = widget.productoRepository
      .watchArticulos();
  bool _byQuantity = false;

  Future<void> _selectPeriod() async {
    final selected = await Navigator.of(context).push<ReportPeriod>(
      MaterialPageRoute(
        builder: (_) => ReportDateFilterScreen(
          initialPeriod: _period,
          today: widget.now?.call() ?? DateTime.now(),
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _period = selected);
  }

  void _open(CategorySalesGroup group) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CategorySalesReportScreen(
        initialPeriod: _period,
        repository: widget.repository,
        productoRepository: widget.productoRepository,
        categoryKey: widget.categoryKey ?? group.key,
        productKey: widget.categoryKey == null ? null : group.key,
        title: group.label,
        now: widget.now,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title ?? 'Informe por categoría')),
    body: Column(
      children: [
        Row(
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
        Expanded(
          child: StreamBuilder<List<ConfirmedSale>>(
            stream: _sales,
            builder: (context, sales) => StreamBuilder<List<ArticuloListado>>(
              stream: _articles,
              builder: (context, articles) {
                if (sales.hasError || articles.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No se pudo cargar el informe.'),
                        TextButton(
                          onPressed: () => setState(() {
                            _sales = widget.repository.watchSales();
                            _articles = widget.productoRepository
                                .watchArticulos();
                          }),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }
                if (!sales.hasData || !articles.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final report = CategorySalesReport.calculate(
                  _period,
                  sales.data!,
                  articles.data!,
                );
                final category = report.categories
                    .where((c) => c.key == widget.categoryKey)
                    .firstOrNull;
                var groups = widget.categoryKey == null
                    ? report.categories
                    : category == null
                    ? <CategorySalesGroup>[]
                    : CategorySalesReport.products(
                        category,
                        byQuantity: _byQuantity,
                      );
                final product = groups
                    .where((g) => g.key == widget.productKey)
                    .firstOrNull;
                if (widget.productKey != null) {
                  groups = product == null ? [] : [product];
                }
                final total = groups.fold(
                  BigInt.zero,
                  (n, g) => n + g.totalMinor,
                );
                final gross = widget.categoryKey == null
                    ? SalesReportsCalculator.grossProfit(_period, sales.data!)
                    : (widget.productKey == null ? category : product)?.gross;
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Clasificado por la categoría actual. Mover productos cambia este informe. Las variantes no disponibles se muestran fuera del catálogo actual.',
                      ),
                    ),
                    Card(
                      child: ListTile(
                        title: const Text('VENTAS NETAS'),
                        subtitle: Text(
                          ReportMoney.signedMoney(total),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ),
                    if (gross != null) BeneficioBrutoReportCard(report: gross),
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Importes y costos registrados en la venta, menos devoluciones y anulaciones por fecha de negocio.',
                      ),
                    ),
                    if (groups.isEmpty)
                      const ListTile(
                        title: Text('Sin operaciones en este período'),
                      ),
                    if (widget.productKey == null && groups.isNotEmpty) ...[
                      CategorySalesChart(groups: groups, onTap: _open),
                      if (widget.categoryKey != null) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Ordenar por importe'),
                              selected: !_byQuantity,
                              onSelected: (_) =>
                                  setState(() => _byQuantity = false),
                            ),
                            ChoiceChip(
                              label: const Text('Ordenar por cantidad'),
                              selected: _byQuantity,
                              onSelected: (_) =>
                                  setState(() => _byQuantity = true),
                            ),
                          ],
                        ),
                        if (_byQuantity)
                          const Text(
                            'Cantidades ordenadas dentro de cada unidad; piezas y medidas se mantienen separadas.',
                          ),
                      ],
                      for (final group in groups)
                        Card(
                          child: ListTile(
                            title: Text(group.label),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.categoryKey == null
                                      ? '${group.saleCount} ventas'
                                      : _quantity(group),
                                ),
                                Text(
                                  '${group.gross.titulo}: ${group.gross.monto ?? '—'}',
                                ),
                                if (group.gross.detalleSinCosto != null)
                                  Text(group.gross.detalleSinCosto!),
                                Text(
                                  total <= BigInt.zero
                                      ? 'Participación: —'
                                      : '${ReportMoney.percentOf(group.totalMinor, total).toStringAsFixed(1)}% de las ventas netas',
                                ),
                              ],
                            ),
                            onTap: () => _open(group),
                            trailing: const Icon(Icons.chevron_right),
                            isThreeLine: false,
                          ),
                        ),
                    ],
                    if (product != null) ...[
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('Cantidad neta: ${_quantity(product)}'),
                      ),
                      for (final entry in product.entries)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              entry.adjustmentId == null
                                  ? Icons.receipt_long
                                  : Icons.undo,
                            ),
                            title: Text(
                              '${entry.adjustmentId == null ? 'Venta' : 'Ajuste de venta'} ${entry.sale.id}',
                            ),
                            subtitle: Text(
                              '${entry.adjustmentId ?? ReportPeriod.formatDate(entry.sale.createdAt.toLocal())}\n${ReportMoney.signedMoney(entry.amountMinor)}',
                            ),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => SaleReceiptScreen(
                                  saleId: entry.sale.id,
                                  repository: widget.repository,
                                  returnButtonLabel: 'Volver al reporte',
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  String _quantity(CategorySalesGroup group) {
    final n = group.quantityAtomic;
    final factor = BigInt.from(group.factor);
    final remainder = n.abs() % factor;
    final fraction = remainder == BigInt.zero
        ? ''
        : '.${remainder.toString().padLeft(group.factor.toString().length - 1, '0').replaceFirst(RegExp(r'0+$'), '')}';
    return '${n.isNegative ? '-' : ''}${n.abs() ~/ factor}$fraction ${group.unit}';
  }
}
