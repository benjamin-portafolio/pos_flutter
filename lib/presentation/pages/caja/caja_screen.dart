import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../application/commands/articulos/producto_command_service.dart';
import '../../../application/commands/cotizaciones/cotizacion_command_service.dart';
import '../../../application/commands/cotizaciones/guardar_cotizacion_command.dart';
import '../../../application/commands/cotizaciones/quotation_already_linked_exception.dart';
import '../../../application/commands/ventas/limpiar_venta_borrador_command.dart';
import '../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/repositories/quotation_repository.dart';
import '../../../domain/repositories/sale_draft_repository.dart';
import '../../../domain/repositories/unidad_inventario_repository.dart';
import '../../../domain/ventas/sale_draft.dart';
import '../../../domain/ventas/sale_draft_item.dart';
import '../../widgets/article_search_bar.dart';
import '../articulos/article_search_screen.dart';
import '../cotizaciones/quotation_ticket_screen.dart';
import 'barcode/barcode_read_gate.dart';
import 'barcode/physical_barcode_reader.dart';
import 'barcode/sale_barcode_read_coordinator.dart';
import 'draft_item_edit_sheet.dart';
import 'models/sale_draft_display.dart';
import 'payment_method_screen.dart';
import 'sale_barcode_scanner_screen.dart';
import 'sale_draft_tabs_bar.dart';
import 'sale_draft_tabs_controller.dart';

class CajaScreen extends StatefulWidget {
  const CajaScreen({
    this.saleDraftRepository,
    this.quotationRepository,
    this.cotizacionCommandService,
    this.ventaBorradorCommandService,
    this.productoRepository,
    this.productoCommandService,
    this.unidadInventarioRepository,
    this.onOpenCaja,
    super.key,
  });

  final SaleDraftRepository? saleDraftRepository;
  final QuotationRepository? quotationRepository;
  final CotizacionCommandService? cotizacionCommandService;
  final VentaBorradorCommandService? ventaBorradorCommandService;
  final ProductoRepository? productoRepository;
  final ProductoCommandService? productoCommandService;
  final UnidadInventarioRepository? unidadInventarioRepository;
  final VoidCallback? onOpenCaja;

  @override
  CajaScreenState createState() => CajaScreenState();
}

class CajaScreenState extends State<CajaScreen> {
  late final _repository =
      widget.saleDraftRepository ?? getIt<SaleDraftRepository>();
  late final _draft = _repository.watchCurrentDraft();
  late final _tabStorage = PageStorage.maybeOf(context);
  late final _tabs = SaleDraftTabsController(
    _repository,
    snapshot:
        _tabStorage?.readState(context, identifier: _repository)
            as SaleDraftTabsSnapshot?,
  )..addListener(_rememberTabs);

  void _rememberTabs() {
    _tabStorage?.writeState(context, _tabs.snapshot, identifier: _repository);
  }

  final _physicalReader = GlobalKey<PhysicalBarcodeReaderState>();
  bool _resolvingReads = false;
  bool get isReaderEnabled => _physicalReader.currentState?.isEnabled == true;
  int? get readerInterruptionGeneration =>
      _physicalReader.currentState?.interruptionGeneration;

  void restoreReader(int? generation) {
    if (mounted && !_busy) {
      _physicalReader.currentState?.enableReader(
        restoringGeneration: generation,
      );
    }
  }

  bool get _physicalReaderAvailable =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.android;

  /// Home/menu deben esperar esta barrera antes de salir o abrir otra ruta.
  Future<bool> prepareToLeave() async {
    if (_busy) return false;
    setState(() => _resolvingReads = true);
    try {
      await _physicalReader.currentState?.finish();
      return mounted;
    } finally {
      if (mounted) setState(() => _resolvingReads = false);
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    final reader = _physicalReader.currentState;
    final restoreMode = reader?.isEnabled == true;
    final generation = reader?.interruptionGeneration;
    setState(() => _resolvingReads = true);
    try {
      await reader?.finish();
      if (mounted) await action();
    } finally {
      if (mounted) {
        setState(() => _resolvingReads = false);
        // La selección puede haber cambiado; reconstruir antes de reabrir el HID.
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && restoreMode) {
          reader?.enableReader(restoringGeneration: generation);
        }
      }
    }
  }

  Future<void> _openSearch() => _runAction(
    () => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ArticleSearchScreen(
          productoRepository:
              widget.productoRepository ?? getIt<ProductoRepository>(),
          saleDraftRepository: _repository,
          ventaBorradorCommandService: widget.ventaBorradorCommandService,
          onOpenCaja: widget.onOpenCaja,
        ),
      ),
    ),
  );

  bool _clearing = false;
  bool _quoting = false;
  GuardarCotizacionCommand? _quotationIntent;
  bool get _busy => _resolvingReads;

  Future<void> _quote() => _runAction(() async {
    final sale = await _repository.watchCurrentDraft().first;
    if (!mounted ||
        sale == null ||
        sale.items.isEmpty ||
        sale.lastEventId == null) {
      return;
    }
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
  });

  Future<void> _openPayment() => _runAction(() async {
    final sale = await _repository.watchCurrentDraft().first;
    if (!mounted || sale == null || sale.items.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PaymentMethodScreen(
          totalMinor: sale.totalMinor,
          saleId: sale.id,
          expectedDraftEventId: sale.lastEventId,
        ),
      ),
    );
  });

  final _barcodeClock = Stopwatch()..start();
  late final _barcodeGate = BarcodeReadGate(clock: () => _barcodeClock.elapsed);

  Future<void> _openBarcodeScanner() => _runAction(() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SaleBarcodeScannerScreen(
          productoRepository: widget.productoRepository,
          saleDraftRepository: _repository,
          ventaBorradorCommandService: widget.ventaBorradorCommandService,
          productoCommandService: widget.productoCommandService,
          readGate: _barcodeGate,
        ),
      ),
    );
  });

  @override
  void dispose() {
    _tabs.removeListener(_rememberTabs);
    _tabs.dispose();
    _barcodeClock.stop();
    super.dispose();
  }

  Future<void> _clear() => _runAction(() async {
    final sale = await _repository.watchCurrentDraft().first;
    if (!mounted || sale == null) return;
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
  });

  Future<void> _openEditor(String itemId) => _runAction(() async {
    final sale = await _repository.watchCurrentDraft().first;
    if (!mounted || sale == null) return;
    final items = sale.items.where((item) => item.id == itemId);
    if (items.isEmpty) return;
    final item = items.single;
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
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        SaleDraftTabsBar(
          controller: _tabs,
          enabled: !_busy,
          onSelect: (index) {
            if (index == _tabs.selectedIndex) return;
            _runAction(() async => _tabs.select(index));
          },
          onAdd: () => _runAction(() async => _tabs.add()),
        ),
        AbsorbPointer(
          absorbing: _busy,
          child: ArticleSearchBar(
            showQuickAdd: false,
            productoRepository: widget.productoRepository,
            saleDraftRepository: _repository,
            ventaBorradorCommandService: widget.ventaBorradorCommandService,
            onOpenCaja: widget.onOpenCaja,
            onOpenSearch: _openSearch,
            onScanBarcode: _busy ? null : _openBarcodeScanner,
          ),
        ),
        if (_physicalReaderAvailable)
          PhysicalBarcodeReader(
            key: _physicalReader,
            productoRepository:
                widget.productoRepository ?? getIt<ProductoRepository>(),
            createArticle: (command) =>
                (widget.productoCommandService ??
                        getIt<ProductoCommandService>())
                    .crearArticulo(command),
            assignBarcode: (command) =>
                (widget.productoCommandService ??
                        getIt<ProductoCommandService>())
                    .asignarCodigoBarrasVariante(command),
            saleDraftRepository:
                widget.saleDraftRepository ?? getIt<SaleDraftRepository>(),
            automaticallyEnabled: defaultTargetPlatform != TargetPlatform.macOS,
            interactionEnabled: !_busy,
            coordinator: SaleBarcodeReadCoordinator(
              products:
                  widget.productoRepository ?? getIt<ProductoRepository>(),
              commands:
                  widget.ventaBorradorCommandService ??
                  getIt<VentaBorradorCommandService>(),
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
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, listConstraints) => ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: (listConstraints.maxHeight - 24)
                                      .clamp(0, double.infinity),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (sale == null || sale.items.isEmpty)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: 32,
                                            ),
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
                                                  var i = sale.items.length - 1;
                                                  i >= 0;
                                                  i--
                                                ) ...[
                                                  if (i < sale.items.length - 1)
                                                    const Divider(height: 1),
                                                  _SaleLine(
                                                    item: sale.items[i],
                                                    onEdit: _busy
                                                        ? null
                                                        : () => _openEditor(
                                                            sale.items[i].id,
                                                          ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Card(
                                      margin: EdgeInsets.zero,
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _AmountRow(
                                              label: 'Subtotal',
                                              amount: total,
                                            ),
                                            const Divider(),
                                            _AmountRow(
                                              label: 'Total general',
                                              amount: total,
                                              bold: true,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              SaleDraftDisplay.summary(sale),
                                            ),
                                            const Wrap(
                                              spacing: 8,
                                              children: [
                                                TextButton(
                                                  onPressed: null,
                                                  child: Text(
                                                    'Agregar impuesto',
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: null,
                                                  child: Text(
                                                    'Agregar descuento',
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: null,
                                                  child: Text(
                                                    'Agregar otros cargos',
                                                  ),
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
                            ],
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * 0.55,
                        ),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FilledButton.icon(
                                  onPressed: sale == null || _busy
                                      ? null
                                      : _clear,
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
                                          : _quote,
                                      icon: const Icon(
                                        Icons.request_quote_outlined,
                                      ),
                                      label: Text(
                                        _quoting ? 'Guardando…' : 'Cotizar',
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed:
                                          sale == null ||
                                              sale.items.isEmpty ||
                                              _busy
                                          ? null
                                          : _openPayment,
                                      child: Text('Cobrar: $total'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
