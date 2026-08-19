import 'package:flutter/material.dart';

import '../../../../../domain/inventario/dimension_unidad.dart';
import '../../../../../domain/inventario/unidad_inventario.dart';

class InventoryUnitPicker {
  const InventoryUnitPicker._();

  static Future<UnidadInventario?> show({
    required BuildContext context,
    required List<UnidadInventario> units,
    UnidadInventario? selected,
  }) {
    return showModalBottomSheet<UnidadInventario>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .72,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                'Unidad predeterminada',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final dimension in DimensionUnidad.values) ...[
                if (units.any((unit) => unit.dimension == dimension)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      dimension.label,
                      key: Key('unit_group_${dimension.code}'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  ...units
                      .where((unit) => unit.dimension == dimension)
                      .map(
                        (unit) => ListTile(
                          key: Key('inventory_unit_${unit.code}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text('${unit.nombre} (${unit.simbolo})'),
                          trailing: selected?.id == unit.id
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.of(context).pop(unit),
                        ),
                      ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
