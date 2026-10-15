import 'package:flutter/material.dart';

import '../../../../domain/articulos/variante_por_codigo_barras.dart';

/// Un código compartido exige elegir explícitamente qué variante editar.
class InventoryBarcodeMatchesDialog extends StatelessWidget {
  const InventoryBarcodeMatchesDialog({required this.matches, super.key});

  final List<VariantePorCodigoBarras> matches;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Elegir coincidencia para editar'),
    content: SizedBox(
      width: 440,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final match in matches)
            ListTile(
              key: ValueKey('inventory_barcode_match_${match.varianteId}'),
              title: Text(match.nombreProducto),
              subtitle: Text(
                match.nombreVariante?.trim().isNotEmpty == true
                    ? match.nombreVariante!
                    : 'Variante sin nombre',
              ),
              trailing: Text(
                '\$${match.precioVentaMenor ~/ 100}.${(match.precioVentaMenor % 100).toString().padLeft(2, '0')}',
              ),
              onTap: () {
                if (ModalRoute.of(context)?.isCurrent == true) {
                  Navigator.of(context).pop(match);
                }
              },
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
    ],
  );
}
