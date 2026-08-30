import 'package:flutter/material.dart';

import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../../domain/inventario/recurso_inventario_listado.dart';

class InventoryResourceCard extends StatelessWidget {
  const InventoryResourceCard({required this.resource, this.onOpen, super.key});

  static const _codec = InventoryQuantityCodec();

  final RecursoInventarioListado resource;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final unit = resource.unidadPredeterminada;
    final quantity = _codec.formatAtomic(resource.existenciaAtomica, unit);
    return Card(
      key: Key('inventory_resource_${resource.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
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
                ],
              ),
              if (!resource.activo) ...[
                const SizedBox(height: 4),
                Text(
                  'Inactivo',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '$quantity ${unit.simbolo}',
                key: Key('inventory_resource_balance_${resource.id}'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
