import 'package:flutter/material.dart';

import '../../../../../domain/articulos/articulo_listado.dart';
import '../../../../../domain/articulos/variante_listado.dart';
import '../../../../../domain/categorias/color_categoria.dart';
import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../categorias/category_color_palette.dart';

class InventoryArticleCard extends StatefulWidget {
  const InventoryArticleCard({required this.articulo, this.onTap, super.key});

  final ArticuloListado articulo;
  final VoidCallback? onTap;

  @override
  State<InventoryArticleCard> createState() => _InventoryArticleCardState();
}

class _InventoryArticleCardState extends State<InventoryArticleCard> {
  static const _quantityCodec = InventoryQuantityCodec();
  late List<VarianteListado> _variants;
  late String _selectedVariantId;

  @override
  void initState() {
    super.initState();
    _updateVariants();
    _selectedVariantId = _variants.first.varianteId;
  }

  @override
  void didUpdateWidget(covariant InventoryArticleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateVariants();
    if (oldWidget.articulo.productoId != widget.articulo.productoId ||
        !_variants.any((variant) => variant.varianteId == _selectedVariantId)) {
      _selectedVariantId = _variants.first.varianteId;
    }
  }

  void _updateVariants() {
    _variants = [...widget.articulo.variantesActivas]
      ..sort((left, right) {
        final byOrder = left.orden.compareTo(right.orden);
        return byOrder != 0
            ? byOrder
            : left.varianteId.compareTo(right.varianteId);
      });
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.articulo;
    final variant = _variants.firstWhere(
      (variant) => variant.varianteId == _selectedVariantId,
    );
    final variantName = variant.nombre?.trim() ?? '';
    final title = variantName.isEmpty
        ? article.nombre
        : '${article.nombre} $variantName';
    final price = _priceLabel(variant);
    final inventory = variant.inventario;
    final stock = inventory == null
        ? null
        : '${_quantityCodec.formatAtomic(inventory.existenciaAtomica, inventory.unidadPredeterminada)} '
              '${inventory.unidadPredeterminada.simbolo} en existencia';
    final category = article.categoriaNombre == null
        ? 'sin categoría'
        : 'categoría ${article.categoriaNombre}';
    final colorScheme = Theme.of(context).colorScheme;
    final categoryColor = CategoryColorPalette.resolve(
      article.categoriaColor ?? ColorCategoria.neutral,
    );

    return Card(
      color: colorScheme.surface,
      surfaceTintColor: colorScheme.surface,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    container: true,
                    label: article.categoriaNombre == null
                        ? 'Artículo sin categoría'
                        : 'Categoría ${article.categoriaNombre}',
                    child: ExcludeSemantics(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: categoryColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color:
                              ThemeData.estimateBrightnessForColor(
                                    categoryColor,
                                  ) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Semantics(
                      container: true,
                      label:
                          '$title, $category, $price'
                          '${stock == null ? '' : ', $stock'}',
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            if (article.categoriaNombre case final name?) ...[
                              const SizedBox(height: 2),
                              Text(
                                name,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 16,
                              runSpacing: 4,
                              children: [
                                Text(
                                  price,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                if (stock != null)
                                  Text(
                                    stock,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
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
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _variants
                    .map((variant) {
                      final selected = variant.varianteId == _selectedVariantId;
                      final name = variant.nombre?.trim() ?? '';
                      return Semantics(
                        selected: selected,
                        child: FilledButton(
                          key: ValueKey(
                            'article_variant_${variant.varianteId}',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(96, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            backgroundColor: selected
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            foregroundColor: selected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                          ),
                          onPressed: () => setState(() {
                            _selectedVariantId = variant.varianteId;
                          }),
                          child: Text(
                            name.isNotEmpty
                                ? name
                                : '< ${_formatPrice(variant.precioVentaMenor, currency: false)} >',
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _priceLabel(VarianteListado variant) {
    final price = _formatPrice(variant.precioVentaMenor);
    final unit = widget.articulo.unidadVenta;
    if (unit == null) return price;
    final quantity = _quantityCodec.formatAtomic(
      widget.articulo.cantidadReferenciaPrecioAtomica!,
      unit,
    );
    return '$price x $quantity ${unit.simbolo}';
  }

  static String _formatPrice(int amountMinor, {bool currency = true}) {
    final absolute = amountMinor.abs();
    final units = absolute ~/ 100;
    final cents = (absolute % 100).toString().padLeft(2, '0');
    final sign = amountMinor < 0 ? '-' : '';
    return '$sign${currency ? r'$' : ''}$units.$cents';
  }
}
