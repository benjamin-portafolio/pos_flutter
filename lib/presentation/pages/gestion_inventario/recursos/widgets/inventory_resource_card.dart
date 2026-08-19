import 'package:flutter/material.dart';

import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../../domain/inventario/recurso_inventario_listado.dart';

class InventoryResourceCard extends StatelessWidget {
  const InventoryResourceCard({required this.resource, super.key});

  static const _codec = InventoryQuantityCodec();

  final RecursoInventarioListado resource;

  @override
  Widget build(BuildContext context) {
    final unit = resource.unidadPredeterminada;
    final quantity = _codec.formatAtomic(resource.existenciaAtomica, unit);
    return Card(
      key: Key('inventory_resource_${resource.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    resource.nombre,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusChip(active: resource.activo),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$quantity ${unit.simbolo}',
              key: Key('inventory_resource_balance_${resource.id}'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            if (resource.vinculadoAVariante || resource.usadoEnRecetas) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (resource.vinculadoAVariante)
                    const Chip(
                      avatar: Icon(Icons.point_of_sale, size: 18),
                      label: Text('Vinculado a variante'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (resource.usadoEnRecetas)
                    Chip(
                      avatar: const Icon(Icons.restaurant_menu, size: 18),
                      label: Text(
                        'Usado en recetas (${resource.cantidadRecetas})',
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (resource.nombresVariantesVinculadas.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Producto/variante: ${resource.nombresVariantesVinculadas.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(active ? 'Activo' : 'Inactivo'),
      visualDensity: VisualDensity.compact,
      backgroundColor: active
          ? const Color(0xFFE8F5E9)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
