import '../../../domain/repositories/confirmed_sale_repository.dart';
import 'confirmed_sales_screen.dart';
import 'package:flutter/material.dart';

import '../../../application/commands/ventas/limpiar_venta_borrador_command.dart';
import '../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/repositories/sale_draft_repository.dart';
import '../../../domain/ventas/sale_draft.dart';
import '../../../domain/ventas/sale_draft_item.dart';
import '../../widgets/article_search_bar.dart';
import 'models/sale_draft_display.dart';
import 'payment_method_screen.dart';

class CajaScreen extends StatefulWidget {
  const CajaScreen({
    this.saleDraftRepository,
    this.ventaBorradorCommandService,
    this.productoRepository,
    this.onOpenCaja,
    super.key,
  });

  final SaleDraftRepository? saleDraftRepository;
  final VentaBorradorCommandService? ventaBorradorCommandService;
  final ProductoRepository? productoRepository;
  final VoidCallback? onOpenCaja;

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  late final _repository =
      widget.saleDraftRepository ?? getIt<SaleDraftRepository>();
  late final _draft = _repository.watchCurrentDraft();
  bool _clearing = false;

  Future<void> _clear(SaleDraft sale) async {
    if (_clearing) return;
    setState(() => _clearing = true);
    try {
      await (widget.ventaBorradorCommandService ??
              getIt<VentaBorradorCommandService>())
          .limpiar(LimpiarVentaBorradorCommand(saleId: sale.id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo limpiar la venta. Intenta nuevamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        if (getIt.isRegistered<ConfirmedSaleRepository>())
          TextButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ConfirmedSalesScreen()),
            ),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Ventas cobradas'),
          ),
        ArticleSearchBar(
          showQuickAdd: false,
          productoRepository: widget.productoRepository,
          saleDraftRepository: _repository,
          ventaBorradorCommandService: widget.ventaBorradorCommandService,
          onOpenCaja: widget.onOpenCaja,
        ),
        Expanded(
          child: StreamBuilder<SaleDraft?>(
            stream: _draft,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('No se pudo cargar la venta.'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final sale = snapshot.data;
              final total = SaleDraftDisplay.money(sale?.totalMinor ?? 0);
              return ColoredBox(
                color: const Color(0xFFE6E6E6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          if (sale == null || sale.items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Text(
                                'La venta está vacía.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            Card(
                              margin: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < sale.items.length;
                                    i++
                                  ) ...[
                                    if (i > 0) const Divider(height: 1),
                                    _SaleLine(item: sale.items[i]),
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          const Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: null,
                                  child: Text('Añadir artículo nuevo'),
                                ),
                              ),
                              SizedBox(width: 8),
                              IconButton.outlined(
                                onPressed: null,
                                tooltip: 'Código de barras',
                                icon: Icon(Icons.qr_code_scanner),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _AmountRow(label: 'Subtotal', amount: total),
                                  const Divider(),
                                  _AmountRow(
                                    label: 'Total general',
                                    amount: total,
                                    bold: true,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(SaleDraftDisplay.summary(sale)),
                                  const Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: null,
                                        child: Text('Agregar impuesto'),
                                      ),
                                      TextButton(
                                        onPressed: null,
                                        child: Text('Agregar descuento'),
                                      ),
                                      TextButton(
                                        onPressed: null,
                                        child: Text('Agregar otros cargos'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: sale == null || _clearing
                                ? null
                                : () => _clear(sale),
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: Text(
                              _clearing ? 'Limpiando…' : 'Limpiar venta',
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed:
                                sale == null || sale.items.isEmpty || _clearing
                                ? null
                                : () => Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => PaymentMethodScreen(
                                        totalMinor: sale.totalMinor,
                                        saleId: sale.id,
                                        expectedDraftEventId: sale.lastEventId,
                                      ),
                                    ),
                                  ),
                            child: Text('Cobrar: $total'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _SaleLine extends StatelessWidget {
  const _SaleLine({required this.item});
  final SaleDraftItem item;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey(item.id),
    padding: const EdgeInsets.all(8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  item.productName,
                  if (item.variantName != null) item.variantName!,
                ].join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${SaleDraftDisplay.quantity(item)} × ${SaleDraftDisplay.price(item)}',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            SaleDraftDisplay.money(item.totalMinor),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });
  final String label;
  final String amount;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          amount,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    ],
  );
}
