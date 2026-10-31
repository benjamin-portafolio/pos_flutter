import 'dart:math' as math;

import '../../../application/commands/articulos/producto_command_service.dart';
import '../../../domain/articulos/codigo_barras.dart';
import '../caja/barcode/physical_barcode_reader.dart';
import '../caja/barcode/sale_barcode_read_coordinator.dart';

import 'package:flutter/material.dart';

import '../../../application/commands/ventas/agregar_producto_borrador_command.dart';
import '../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/articulos/articulo_listado.dart';
import '../../../domain/categorias/color_categoria.dart';
import '../../../domain/inventario/dimension_unidad.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/repositories/sale_draft_repository.dart';
import '../../../domain/ventas/sale_draft.dart';
import '../caja/models/sale_draft_display.dart';
import '../caja/weighing/sale_measured_quantity_dialog.dart';
import '../gestion_inventario/categorias/category_color_palette.dart';
import 'models/article_search_item.dart';
import 'sale_quantity_form_result.dart';

class ArticleSearchScreen extends StatefulWidget {
  const ArticleSearchScreen({
    required this.productoRepository,
    this.ventaBorradorCommandService,
    this.saleDraftRepository,
    this.onOpenCaja,
    this.initialQuery = '',
    this.cajaBarcodeSearch = false,
    this.productoCommandService,
    super.key,
  });

  final String initialQuery;
  final bool cajaBarcodeSearch;
  final ProductoCommandService? productoCommandService;
  final SaleDraftRepository? saleDraftRepository;
  final VoidCallback? onOpenCaja;

  final VentaBorradorCommandService? ventaBorradorCommandService;

  final ProductoRepository productoRepository;

  @override
  State<ArticleSearchScreen> createState() => _ArticleSearchScreenState();
}

class _ArticleSearchScreenState extends State<ArticleSearchScreen> {
  bool _adding = false;
  late final _draft =
      (widget.saleDraftRepository ?? getIt<SaleDraftRepository>())
          .watchCurrentDraft();

  final _reader = GlobalKey<PhysicalBarcodeReaderState>();
  bool _returning = false;
  bool _allowPop = false;
  List<ArticuloListado>? _catalog;

  bool _shouldSubmit(String input) {
    final catalog = _catalog;
    if (catalog == null) return false;
    final String? code;
    try {
      code = CodigoBarras.fromInput(input).value;
    } on ArgumentError {
      return false;
    }
    if (code == null) return false;
    final matches = ArticleSearchItem.search(
      catalog,
      code,
      includeBarcode: true,
    );
    if (matches.any((item) => item.variant.codigoBarras == code)) return true;
    // Un nombre numérico o un fragmento conserva los resultados. Solo una
    // entrada sin coincidencias ofrece el recorrido de código desconocido.
    return matches.isEmpty;
  }

  Future<void> _returnToCaja() async {
    if (_adding || _returning) return;
    setState(() => _returning = true);
    await _reader.currentState?.finish();
    if (mounted) {
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) _openCaja();
    }
  }

  void _openCaja() {
    _focusNode.unfocus();
    Navigator.of(context).pop();
    widget.onOpenCaja?.call();
  }

  Future<void> _add(ArticleSearchItem item) async {
    if (_adding) return;
    setState(() => _adding = true);
    _focusNode.unfocus();
    final reader = _reader.currentState;
    final generation = reader?.interruptionGeneration;
    try {
      // La selección manual también espera todas las lecturas ya aceptadas.
      await reader?.finish(keepInputFocus: true);
      if (!mounted) return;
      final commands =
          widget.ventaBorradorCommandService ??
          getIt<VentaBorradorCommandService>();
      final capture = await commands.prepararCaptura(item.variant.varianteId);
      if (!mounted) return;
      final unit = item.article.unidadVenta;
      SaleQuantityFormResult? amount;
      if (unit != null) {
        amount = await showDialog<SaleQuantityFormResult>(
          context: context,
          builder: (_) => SaleMeasuredQuantityDialog(
            allowWeighing: true,
            loadConditions: () async => capture.measured,
            watchDraft:
                (widget.saleDraftRepository ?? getIt<SaleDraftRepository>())
                    .watchCurrentDraft,
          ),
        );
        if (amount == null || !mounted) {
          if (mounted && widget.cajaBarcodeSearch) {
            _message('Cantidad cancelada.');
          }
          return;
        }
      }
      await commands.agregar(
        capture.bind(
          amount?.toCommand(item.variant.varianteId) ??
              AgregarProductoBorradorCommand(
                variantId: item.variant.varianteId,
              ),
        ),
      );
      if (mounted) {
        if (unit?.dimension == DimensionUnidad.mass) {
          if (widget.cajaBarcodeSearch) {
            reader?.clearInput();
          } else {
            setState(_controller.clear);
            _focusNode.requestFocus();
          }
        }
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } on StateError catch (error) {
      if (mounted) _message(error.message.toString());
    } catch (_) {
      if (mounted) {
        _message('No se pudo agregar el artículo. Intenta nuevamente.');
      }
    } finally {
      if (mounted) {
        setState(() => _adding = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) reader?.enableReader(restoringGeneration: generation);
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  late final _controller = TextEditingController(text: widget.initialQuery);
  final _focusNode = FocusNode();
  late final Stream<List<ArticuloListado>> _articles = widget.productoRepository
      .watchArticulos();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return PopScope(
      canPop: !widget.cajaBarcodeSearch || _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.cajaBarcodeSearch) _returnToCaja();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE6E6E6),
        appBar: AppBar(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: widget.cajaBarcodeSearch
              ? const Text('Buscar artículos')
              : TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _focusNode.unfocus(),
                  decoration: InputDecoration(
                    hintText: 'Quiero vender…',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: BackButton(color: primary),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(_controller.clear);
                              _focusNode.requestFocus();
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
          toolbarHeight: 76,
        ),
        body: SafeArea(
          child: StreamBuilder<SaleDraft?>(
            stream: _draft,
            builder: (context, draftSnapshot) {
              final draft = draftSnapshot.hasError ? null : draftSnapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.cajaBarcodeSearch)
                    PhysicalBarcodeReader(
                      key: _reader,
                      searchMode: true,
                      interactionEnabled: !_adding && !_returning,
                      initialText: widget.initialQuery,
                      shouldSubmit: _shouldSubmit,
                      onQueryChanged: (query) {
                        if (mounted) setState(() => _controller.text = query);
                      },
                      onBack: _returnToCaja,
                      onAdded: _returnToCaja,
                      productoRepository: widget.productoRepository,
                      saleDraftRepository:
                          widget.saleDraftRepository ??
                          getIt<SaleDraftRepository>(),
                      assignBarcode: (command) =>
                          (widget.productoCommandService ??
                                  getIt<ProductoCommandService>())
                              .asignarCodigoBarrasVariante(command),
                      createArticle: (command) =>
                          (widget.productoCommandService ??
                                  getIt<ProductoCommandService>())
                              .crearArticulo(command),
                      coordinator: SaleBarcodeReadCoordinator(
                        products: widget.productoRepository,
                        commands:
                            widget.ventaBorradorCommandService ??
                            getIt<VentaBorradorCommandService>(),
                      ),
                    ),
                  if (draftSnapshot.hasError)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'No se pudieron cargar las cantidades de la venta.',
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<ArticuloListado>>(
                      stream: _articles,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text('No se pudieron cargar los artículos.'),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        _catalog = snapshot.data!;
                        final searching = _controller.text.trim().isNotEmpty;
                        final results = ArticleSearchItem.search(
                          snapshot.data!,
                          _controller.text,
                          includeBarcode: widget.cajaBarcodeSearch,
                        );
                        if (results.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                searching
                                    ? 'No se encontraron artículos.'
                                    : 'No hay artículos.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              child: Text(
                                searching
                                    ? 'Resultados'
                                    : 'Recientemente añadidos',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final width = constraints.maxWidth - 24;
                                  final columns = (width / 100).floor().clamp(
                                    2,
                                    6,
                                  );
                                  final tileWidth =
                                      (width - (columns - 1) * 8) / columns;
                                  final circleSize = math.min(
                                    100.0,
                                    tileWidth * 0.64,
                                  );
                                  final scaler = MediaQuery.textScalerOf(
                                    context,
                                  );
                                  // Reserva dos líneas por nombre y una para el precio,
                                  // también cuando el usuario amplía el texto.
                                  final tileHeight =
                                      circleSize +
                                      32 +
                                      scaler.scale(14) * 1.2 * 3 +
                                      scaler.scale(12) * 1.2 * 2;
                                  return GridView.builder(
                                    key: ValueKey(_controller.text),
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      4,
                                      12,
                                      12,
                                    ),
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          crossAxisSpacing: 8,
                                          mainAxisSpacing: 8,
                                          mainAxisExtent: tileHeight,
                                        ),
                                    itemCount: results.length,
                                    itemBuilder: (context, index) =>
                                        _ArticleSearchTile(
                                          key: ValueKey(
                                            results[index].variant.varianteId,
                                          ),
                                          item: results[index],
                                          quantityLabel: draft == null
                                              ? ''
                                              : SaleDraftDisplay.badge(
                                                  draft,
                                                  results[index]
                                                      .variant
                                                      .varianteId,
                                                ),
                                          circleSize: circleSize,
                                          onTap: _adding
                                              ? null
                                              : () => _add(results[index]),
                                        ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (draft != null && draft.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                        onPressed: _adding || _returning
                            ? null
                            : widget.cajaBarcodeSearch
                            ? _returnToCaja
                            : _openCaja,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
                        child: Text(
                          'Ir a caja (${draft.articleCount} ${draft.articleCount == 1 ? 'artículo' : 'artículos'})',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ArticleSearchTile extends StatelessWidget {
  const _ArticleSearchTile({
    required this.item,
    required this.circleSize,
    required this.quantityLabel,
    required this.onTap,
    super.key,
  });

  final ArticleSearchItem item;
  final double circleSize;
  final String quantityLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final variantName = item.variant.nombre?.trim();
    final minor = item.variant.precioVentaMenor;
    final price =
        '\$${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
    return Semantics(
      label: [
        item.article.nombre,
        if (variantName != null && variantName.isNotEmpty) variantName,
        price,
        if (quantityLabel.isNotEmpty) 'En la venta: $quantityLabel',
      ].join(', '),
      excludeSemantics: true,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(6),
                  foregroundDecoration: quantityLabel.isEmpty
                      ? null
                      : const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0x22000000),
                        ),
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CategoryColorPalette.resolve(
                      item.article.categoriaColor ?? ColorCategoria.grey,
                    ),
                  ),
                  child: quantityLabel.isEmpty
                      ? null
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            quantityLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.article.nombre,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (variantName != null && variantName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    variantName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: Color(0xFF616161),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    price,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
