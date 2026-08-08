import 'package:flutter/material.dart';

import '../../../../../domain/articulos/articulo_listado.dart';
import '../../../../../domain/articulos/variante_listado.dart';
import '../../../../../domain/categorias/color_categoria.dart';
import '../../categorias/category_color_palette.dart';

class InventoryArticleCard extends StatelessWidget {
  const InventoryArticleCard({required this.articulo, super.key});

  final ArticuloListado articulo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final categoryColor = CategoryColorPalette.resolve(
      articulo.categoriaColor ?? ColorCategoria.neutral,
    );
    final namedVariants =
        articulo.variantesActivas
            .where((variant) => variant.nombre?.trim().isNotEmpty ?? false)
            .toList(growable: false)
          ..sort(_compareVariants);

    return Semantics(
      container: true,
      label: _semanticLabel,
      child: Card(
        color: colorScheme.surface,
        surfaceTintColor: colorScheme.surface,
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: articulo.categoriaNombre == null
                    ? 'Artículo sin categoría'
                    : 'Categoría ${articulo.categoriaNombre}',
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
                          ThemeData.estimateBrightnessForColor(categoryColor) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        articulo.nombre,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (articulo.categoriaNombre
                          case final categoryName?) ...[
                        const SizedBox(height: 2),
                        Text(
                          categoryName,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        _formatPrice(articulo.precioPredeterminadoMenor),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (namedVariants.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: namedVariants
                              .map(
                                (variant) => Chip(
                                  key: ValueKey(
                                    'article_variant_${variant.varianteId}',
                                  ),
                                  label: Text(
                                    '${variant.nombre} · '
                                    '${_formatPrice(variant.precioVentaMenor)}',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _semanticLabel {
    final category = articulo.categoriaNombre == null
        ? 'sin categoría'
        : 'categoría ${articulo.categoriaNombre}';
    return '${articulo.nombre}, $category, '
        '${_formatPrice(articulo.precioPredeterminadoMenor)}';
  }

  static int _compareVariants(VarianteListado left, VarianteListado right) {
    final byOrder = left.orden.compareTo(right.orden);
    if (byOrder != 0) return byOrder;
    final byName = (left.nombre ?? '').compareTo(right.nombre ?? '');
    if (byName != 0) return byName;
    return left.varianteId.compareTo(right.varianteId);
  }

  static String _formatPrice(int amountMinor) {
    final absolute = amountMinor.abs();
    final units = absolute ~/ 100;
    final cents = (absolute % 100).toString().padLeft(2, '0');
    final sign = amountMinor < 0 ? '-' : '';
    return '$sign\$$units.$cents';
  }
}
