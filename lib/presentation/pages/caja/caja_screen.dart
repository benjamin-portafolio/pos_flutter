import '../../../application/commands/cotizaciones/cotizacion_command_service.dart';
import '../../../application/commands/cotizaciones/guardar_cotizacion_command.dart';
import '../../../application/commands/cotizaciones/quotation_already_linked_exception.dart';
import '../../../domain/repositories/quotation_repository.dart';
import '../cotizaciones/quotation_ticket_screen.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import 'confirmed_sales_screen.dart';
import 'package:flutter/material.dart';

import '../../../application/commands/ventas/limpiar_venta_borrador_command.dart';
import '../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/repositories/sale_draft_repository.dart';
import '../../../domain/repositories/unidad_inventario_repository.dart';
import '../../../domain/ventas/sale_draft.dart';
import '../../../domain/ventas/sale_draft_item.dart';
import '../../widgets/article_search_bar.dart';
import 'draft_item_edit_sheet.dart';
import 'barcode/barcode_read_gate.dart';
import 'models/sale_draft_display.dart';
import 'payment_method_screen.dart';
import 'sale_barcode_scanner_screen.dart';

class CajaScreen extends StatefulWidget {
  const CajaScreen({
    this.saleDraftRepository,
    this.quotationRepository,
    this.cotizacionCommandService,
    this.ventaBorradorCommandService,
    this.productoRepository,
    this.unidadInventarioRepository,
    this.onOpenCaja,
    super.key,
  });

  final SaleDraftRepository? saleDraftRepository;
  final QuotationRepository? quotationRepository;
  final CotizacionCommandService? cotizacionCommandService;
  final VentaBorradorCommandService? ventaBorradorCommandService;
  final ProductoRepository? productoRepository;
  final UnidadInventarioRepository? unidadInventarioRepository;
  final VoidCallback? onOpenCaja;

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  late final _repository =
      widget.saleDraftRepository ?? getIt<SaleDraftRepository>();
  late final _draft = _repository.watchCurrentDraft();
  bool _clearing = false;
  bool _scannerOpen = false;
  bool _quoting = false;
  bool _routeOpen = false;
  GuardarCotizacionCommand? _quotationIntent;
  bool get _busy => _clearing || _quoting || _scannerOpen || _routeOpen;

  Future<void> _quote(SaleDraft sale) async {
    if (_busy || sale.items.isEmpty || sale.lastEventId == null) return;
    setState(() => _quoting = true);
    try {
      if (_quotationIntent?.saleId != sale.id ||
          _quotationIntent?.expectedDraftEventId != sale.lastEventId) {
        _quotationIntent = GuardarCotizacionCommand(
          saleId: sale.id,
          expectedDraftEventId: sale.lastEventId!,
        );
      }
      String quotationId;
      LimpiarVentaBorradorCommand? emissionDraft;
      try {
        final result =
            await (widget.cotizacionCommandService ??
                    getIt<CotizacionCommandService>())
                .guardar(_quotationIntent!);
        quotationId = result.quotationId;
        emissionDraft = LimpiarVentaBorradorCommand(
          saleId: sale.id,
          expectedDraftEventId: sale.lastEventId,
        );
      } on QuotationAlreadyLinkedException catch (linked) {
        quotationId = linked.quotationId;
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => QuotationTicketScreen(
            quotationId: quotationId,
            repository: widget.quotationRepository,
            emissionDraft: emissionDraft,
            draftCommands: widget.ventaBorradorCommandService,
          ),
        ),
      );
      // Una consulta posterior se abre como historial, sin limpiar la captura.
      _quotationIntent = null;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar la cotización. Revisa la captura e intenta nuevamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _openPayment(SaleDraft sale) async {
    if (_busy) return;
    setState(() => _routeOpen = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PaymentMethodScreen(
            totalMinor: sale.totalMinor,
            saleId: sale.id,
            expectedDraftEventId: sale.lastEventId,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _routeOpen = false);
    }
  }

  final _barcodeClock = Stopwatch()..start();
  late final _barcodeGate = BarcodeReadGate(clock: () => _barcodeClock.elapsed);

  Future<void> _openBarcodeScanner() async {
    if (_busy) return;
    setState(() => _scannerOpen = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SaleBarcodeScannerScreen(
            productoRepository: widget.productoRepository,
            saleDraftRepository: _repository,
            ventaBorradorCommandService: widget.ventaBorradorCommandService,
            readGate: _barcodeGate,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _scannerOpen = false);
    }
  }

  @override
  void dispose() {
    _barcodeClock.stop();
    super.dispose();
  }

  Future<void> _clear(SaleDraft sale) async {
    if (_busy) return;
    setState(() => _clearing = true);
    try {
      await (widget.ventaBorradorCommandService ??
              getIt<VentaBorradorCommandService>())
          .limpiar(
            LimpiarVentaBorradorCommand(
              saleId: sale.id,
              expectedDraftEventId: sale.lastEventId,
            ),
          );
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

  Future<void> _openEditor(SaleDraftItem item) async {
    if (_busy) return;
    setState(() => _routeOpen = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraftItemEditSheet(
          item: item,
          ventaBorradorCommandService: widget.ventaBorradorCommandService,
          unidadInventarioRepository:
              widget.unidadInventarioRepository ??
              getIt<UnidadInventarioRepository>(),
        ),
      );
    } finally {
      if (mounted) setState(() => _routeOpen = false);
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
        AbsorbPointer(
          absorbing: _busy,
          child: ArticleSearchBar(
            showQuickAdd: false,
            productoRepository: widget.productoRepository,
            saleDraftRepository: _repository,
            ventaBorradorCommandService: widget.ventaBorradorCommandService,
            onOpenCaja: widget.onOpenCaja,
            onScanBarcode: _busy ? null : _openBarcodeScanner,
          ),
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
                                    _SaleLine(
                                      item: sale.items[i],
                                      onEdit: _busy
                                          ? null
                                          : () => _openEditor(sale.items[i]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Expanded(
                                child: OutlinedButton(
                                  onPressed: null,
                                  child: Text('Añadir artículo nuevo'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                onPressed: _busy ? null : _openBarcodeScanner,
                                tooltip: 'Escanear código de barras',
                                icon: const Icon(Icons.barcode_reader),
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
                            onPressed: sale == null || _busy
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
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    sale == null ||
                                        sale.items.isEmpty ||
                                        sale.lastEventId == null ||
                                        _busy
                                    ? null
                                    : () => _quote(sale),
                                icon: const Icon(Icons.request_quote_outlined),
                                label: Text(
                                  _quoting ? 'Guardando…' : 'Cotizar',
                                ),
                              ),
                              FilledButton(
                                onPressed:
                                    sale == null || sale.items.isEmpty || _busy
                                    ? null
                                    : () => _openPayment(sale),
                                child: Text('Cobrar: $total'),
                              ),
                            ],
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
  const _SaleLine({required this.item, required this.onEdit});
  final SaleDraftItem item;
  final VoidCallback? onEdit;

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
        IconButton(
          onPressed: onEdit,
          tooltip: 'Editar artículo',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.edit, size: 18),
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
