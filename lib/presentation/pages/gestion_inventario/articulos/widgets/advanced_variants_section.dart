import 'package:flutter/material.dart';

import '../../../../../domain/articulos/costo_estandar.dart';
import '../../../../../domain/articulos/precio_venta.dart';
import '../models/articulo_form_result.dart';

class AdvancedVariantsSection extends StatelessWidget {
  const AdvancedVariantsSection({
    required this.variants,
    required this.enabled,
    required this.error,
    required this.onEdit,
    required this.onAdd,
    super.key,
  });

  final List<ArticuloFormVarianteResult> variants;
  final bool enabled;
  final String? error;
  final ValueChanged<int> onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < variants.length; index++) ...[
          _VariantDraftCard(
            key: Key('article_variant_card_$index'),
            variant: variants[index],
            enabled: enabled,
            onTap: () => onEdit(index),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          key: const Key('add_article_variant_button'),
          onPressed: enabled ? onAdd : null,
          icon: const Icon(Icons.add),
          label: const Text('Agregar variante'),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            key: const Key('article_variants_error'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: errorColor),
          ),
        ],
      ],
    );
  }
}

class _VariantDraftCard extends StatelessWidget {
  const _VariantDraftCard({
    required this.variant,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final ArticuloFormVarianteResult variant;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cost = _parsedCost(variant.costoEstandar);
    final hasCost = cost != null;
    final costSemantics = hasCost
        ? 'Costo estándar registrado'
        : 'Sin costo estándar';
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      variant.nombre ?? 'Variante sin nombre',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Tooltip(
                    message: costSemantics,
                    child: Semantics(
                      label: costSemantics,
                      child: Icon(
                        Icons.payments_outlined,
                        key: const Key('variant_standard_cost_icon'),
                        color: hasCost ? colorScheme.primary : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _VariantMetric(
                    label: 'Precio de venta',
                    value: _formatDraftPrice(variant.precioVenta),
                  ),
                  _VariantMetric(
                    label: 'Costo estándar (opcional)',
                    value: cost == null ? '—' : _formatMoney(cost),
                  ),
                  const _VariantMetric(
                    label: 'Existencias disponibles',
                    value: '—',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static int? _parsedCost(String? input) {
    try {
      return CostoEstandar.fromInput(input)?.unidadMenor;
    } on ArgumentError {
      return null;
    }
  }

  static String _formatDraftPrice(String input) {
    try {
      return _formatMoney(PrecioVenta.fromInput(input).unidadMenor);
    } on ArgumentError {
      return '—';
    }
  }

  static String _formatMoney(int minor) {
    final whole = minor ~/ 100;
    final cents = (minor % 100).toString().padLeft(2, '0');
    return '\$$whole.$cents';
  }
}

class _VariantMetric extends StatelessWidget {
  const _VariantMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 210),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}
