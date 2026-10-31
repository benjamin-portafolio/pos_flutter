import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../application/commands/articulos/producto_command_service.dart';
import '../../../application/commands/cotizaciones/cotizacion_command_service.dart';
import '../../../application/commands/cotizaciones/guardar_cotizacion_command.dart';
import '../../../application/commands/cotizaciones/quotation_already_linked_exception.dart';
import '../../../application/commands/ventas/cambiar_tarifa_venta_borrador_command.dart';
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
import 'draft_item_inline_editor.dart';
import 'models/sale_draft_display.dart';
import 'payment_method_screen.dart';
import 'sale_barcode_scanner_screen.dart';
import 'sale_draft_tabs_bar.dart';
import 'sale_pricing_review_dialog.dart';
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
  late var _draft = _repository.watchCurrentDraft();
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
  bool get isReaderEnabled =>
      _physicalReader.currentState?.isEnabled == true ||
      _restoreReaderAfterEdit;
  int? get readerInterruptionGeneration =>
      _physicalReader.currentState?.interruptionGeneration;

  void restoreReader(int? generation) {
    if (mounted && !_busy && _editingItemId == null) {
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
    setState(() {
      _resolvingReads = true;
      _editingItemId = null;
      _restoreReaderAfterEdit = false;
    });
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
    final restoreMode = reader?.isEnabled == true || _restoreReaderAfterEdit;
    final generation = _restoreReaderAfterEdit
        ? _editorReaderGeneration
        : reader?.interruptionGeneration;
    setState(() {
      _resolvingReads = true;
      _editingItemId = null;
      _restoreReaderAfterEdit = false;
    });
    try {
      await reader?.finish();
      if (mounted) await action();
    } finally {
      if (mounted) {
        if (_editingItemId != null && restoreMode) {
          _restoreReaderAfterEdit = true;
          _editorReaderGeneration = generation;
        }
        setState(() => _resolvingReads = false);
        // La selección puede haber cambiado; reconstruir antes de reabrir el HID.
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && restoreMode && _editingItemId == null) {
          reader?.enableReader(restoringGeneration: generation);
        }
      }
    }
  }

  Future<void> _openSearch([String initialQuery = '']) => _runAction(
    () => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ArticleSearchScreen(
          productoRepository:
              widget.productoRepository ?? getIt<ProductoRepository>(),
          saleDraftRepository: _repository,
          ventaBorradorCommandService: widget.ventaBorradorCommandService,
          initialQuery: initialQuery,
          cajaBarcodeSearch: true,
          productoCommandService: widget.productoCommandService,
        ),
      ),
    ),
  );

  bool _clearing = false;
  bool _quoting = false;
  GuardarCotizacionCommand? _quotationIntent;
  String? _editingItemId;
  bool _editorSaving = false;
  bool _restoreReaderAfterEdit = false;
  int? _editorReaderGeneration;
  bool get _busy => _resolvingReads || _editorSaving;

  CambiarTarifaVentaBorradorCommand? _pricingIntent;

  Future<void> _togglePricing() => _runAction(() async {
    try {
      final sale = await _repository.watchCurrentDraft().first;
      if (!mounted) return;
      final saleId = sale?.id ?? _repository.selectedDraftId;
      if (saleId == null) return;
      final mode = sale?.pricingMode == 'offer' ? 'normal' : 'offer';
      final previous = _pricingIntent;
      final command =
          previous != null &&
              previous.saleId == saleId &&
              previous.pricingMode == mode &&
              previous.expectedVersion == (sale?.version ?? 0) &&
              previous.expectedDraftEventId == sale?.lastEventId &&
              previous.expectedTotalMinor == (sale?.totalMinor ?? 0)
          ? previous
          : CambiarTarifaVentaBorradorCommand(
              operationId: const Uuid().v4(),
              saleId: saleId,
              pricingMode: mode,
              expectedVersion: sale?.version ?? 0,
              expectedDraftEventId: sale?.lastEventId,
              expectedTotalMinor: sale?.totalMinor ?? 0,
            );
      _pricingIntent = command;
      final commands =
          widget.ventaBorradorCommandService ??
          getIt<VentaBorradorCommandService>();
      if (sale != null && sale.items.isNotEmpty) {
        final preview = await commands.previewTarifa(command);
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (_) => SalePricingReviewDialog(preview: preview),
        );
        if (accepted != true || !mounted) {
          _pricingIntent = null;
          return;
        }
      }
      await commands.cambiarTarifa(command);
      _pricingIntent = null;
    } catch (error) {
      if (mounted) {
        final message = error is StateError
            ? error.message
            : error is FormatException
            ? error.message
            : 'No se pudo guardar el cambio.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo confirmar el cambio de tarifa. $message '
              'Revisa la venta actual antes de volver a intentar.',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      // Líneas, tarifa y total siempre vuelven a la misma lectura persistida.
      if (mounted) setState(() => _draft = _repository.watchCurrentDraft());
    }
  });

  Future<void> _closeEditor() async {
    if (mounted) await _runAction(() async {});
  }

  void _setEditorSaving(bool saving) {
    if (mounted) setState(() => _editorSaving = saving);
  }

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

  Future<void> _openPayment({bool enteredWithEnter = false}) =>
      _runAction(() async {
        final sale = await _repository.watchCurrentDraft().first;
        if (!mounted || sale == null || sale.items.isEmpty) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => PaymentMethodScreen(
              totalMinor: sale.totalMinor,
              saleId: sale.id,
              expectedDraftEventId: sale.lastEventId,
              expectedVersion: sale.version,
              consumeOpeningEnter: enteredWithEnter,
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
    setState(() => _editingItemId = items.single.id);
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
        if (!_physicalReaderAvailable)
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
            onOpenSearch: _openSearch,
            onScanBarcode: _openBarcodeScanner,
            onCharge: _busy ? null : () => _openPayment(enteredWithEnter: true),
            interactionEnabled: !_busy && _editingItemId == null,
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Semantics(
                          key: const Key('sale_pricing_state'),
                          toggled: sale?.pricingMode == 'offer',
                          child: OutlinedButton.icon(
                            key: const Key('sale_offer_toggle'),
                            onPressed: _busy ? null : _togglePricing,
                            style: sale?.pricingMode == 'offer'
                                ? OutlinedButton.styleFrom(
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                  )
                                : null,
                            icon: Icon(
                              sale?.pricingMode == 'offer'
                                  ? Icons.local_offer
                                  : Icons.local_offer_outlined,
                            ),
                            label: Text(
                              'Precio de oferta · '
                              '${sale?.pricingMode == 'offer' ? 'Activo' : 'Normal'}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
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
                                                    key: ValueKey(
                                                      sale.items[i].id,
                                                    ),
                                                    item: sale.items[i],
                                                    offerMode:
                                                        sale.pricingMode ==
                                                        'offer',
                                                    selected:
                                                        _editingItemId ==
                                                        sale.items[i].id,
                                                    editor:
                                                        _editingItemId ==
                                                            sale.items[i].id
                                                        ? DraftItemInlineEditor(
                                                            item: sale.items[i],
                                                            enabled: !_busy,
                                                            ventaBorradorCommandService:
                                                                widget
                                                                    .ventaBorradorCommandService,
                                                            unidadInventarioRepository:
                                                                widget
                                                                    .unidadInventarioRepository,
                                                            onClose:
                                                                _closeEditor,
                                                            onSavingChanged:
                                                                _setEditorSaving,
                                                          )
                                                        : null,
                                                    onEdit: _busy
                                                        ? null
                                                        : () => _openEditor(
                                                            sale.items[i].id,
                                                          ),
                                                    onClose: _busy
                                                        ? null
                                                        : _closeEditor,
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
                                              label: 'Total general',
                                              amount: total,
                                              bold: true,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              SaleDraftDisplay.summary(sale),
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
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: FilledButton.icon(
                                    onPressed: sale == null || _busy
                                        ? null
                                        : _clear,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.delete_sweep_outlined,
                                      size: 18,
                                    ),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _clearing
                                            ? 'Limpiando…'
                                            : 'Limpiar venta',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        sale == null ||
                                            sale.items.isEmpty ||
                                            sale.lastEventId == null ||
                                            _busy
                                        ? null
                                        : _quote,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.request_quote_outlined,
                                      size: 18,
                                    ),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _quoting ? 'Guardando…' : 'Cotizar',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 4,
                                  child: FilledButton(
                                    onPressed:
                                        sale == null ||
                                            sale.items.isEmpty ||
                                            _busy
                                        ? null
                                        : () => _openPayment(),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Cobrar: $total'),
                                    ),
                                  ),
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
  const _SaleLine({
    required this.item,
    required this.offerMode,
    required this.onEdit,
    required this.onClose,
    required this.selected,
    required this.editor,
    super.key,
  });
  final SaleDraftItem item;
  final bool offerMode;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;
  final bool selected;
  final Widget? editor;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: selected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
        : Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                    Text(
                      item.effectivePriceOrigin == 'offer'
                          ? 'Oferta aplicada'
                          : item.effectivePriceOrigin == 'unknown'
                          ? 'Precio capturado · tarifa sin acreditar'
                          : offerMode && item.offerPriceMinorSnapshot == null
                          ? 'Precio normal · sin oferta capturada'
                          : 'Precio normal',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${SaleDraftDisplay.quantity(item)} × ${SaleDraftDisplay.price(item)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
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
                onPressed: selected ? onClose : onEdit,
                tooltip: selected ? 'Cerrar edición' : 'Editar artículo',
                icon: Icon(selected ? Icons.close : Icons.edit, size: 18),
              ),
            ],
          ),
          ?editor,
        ],
      ),
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
