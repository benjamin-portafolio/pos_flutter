import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../application/commands/agregar_producto_borrador_command.dart';
import '../../../application/commands/venta_borrador_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/articulos/articulo_listado.dart';
import '../../../domain/categorias/color_categoria.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/repositories/sale_draft_repository.dart';
import '../../../domain/ventas/sale_draft.dart';
import '../caja/models/sale_draft_display.dart';
import '../gestion_inventario/categorias/category_color_palette.dart';
import 'models/article_search_item.dart';
import 'sale_quantity_dialog.dart';

class ArticleSearchScreen extends StatefulWidget {
  const ArticleSearchScreen({
    required this.productoRepository,
    this.ventaBorradorCommandService,
    this.saleDraftRepository,
    this.onOpenCaja,
    super.key,
  });

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

  void _openCaja() {
    _focusNode.unfocus();
    Navigator.of(context).pop();
    widget.onOpenCaja?.call();
  }

  Future<void> _add(ArticleSearchItem item) async {
    if (_adding) return;
    setState(() => _adding = true);
    _focusNode.unfocus();
    try {
      final unit = item.article.unidadVenta;
      String? amount;
      if (unit != null) {
        amount = await showDialog<String>(
          context: context,
          builder: (_) => SaleQuantityDialog(
            productName: [
              item.article.nombre,
              if (item.variant.nombre != null) item.variant.nombre!,
            ].join(' · '),
            unit: unit,
          ),
        );
        if (amount == null || !mounted) return;
      }
      await (widget.ventaBorradorCommandService ??
              getIt<VentaBorradorCommandService>())
          .agregar(
            AgregarProductoBorradorCommand(
              variantId: item.variant.varianteId,
              measuredQuantity: amount,
              expectedUnitId: unit?.id,
            ),
          );
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } on StateError catch (error) {
      if (mounted) _message(error.message.toString());
    } catch (_) {
      if (mounted) {
        _message('No se pudo agregar el artículo. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  final _controller = TextEditingController();
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
    return Scaffold(
      backgroundColor: const Color(0xFFE6E6E6),
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: TextField(
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                        return const Center(child: CircularProgressIndicator());
                      }
                      final searching = _controller.text.trim().isNotEmpty;
                      final results = ArticleSearchItem.search(
                        snapshot.data!,
                        _controller.text,
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
                                final scaler = MediaQuery.textScalerOf(context);
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
                                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                      onPressed: _adding ? null : _openCaja,
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
