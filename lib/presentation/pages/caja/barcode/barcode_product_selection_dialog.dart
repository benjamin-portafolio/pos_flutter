import 'package:flutter/material.dart';

import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../models/sale_draft_display.dart';

/// Resuelve un barcode compartido sin elegir por el orden de la consulta.
class BarcodeProductSelectionDialog extends StatelessWidget {
  const BarcodeProductSelectionDialog({required this.candidates, super.key});

  final List<VariantePorCodigoBarras> candidates;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('Elige el artículo'),
    children: [
      for (final candidate in candidates)
        ListTile(
          key: ValueKey('barcode_candidate_${candidate.varianteId}'),
          title: Text(candidate.nombreProducto),
          subtitle: Text(
            [
              candidate.nombreVariante ?? 'Sin variante',
              _price(candidate),
            ].join(' · '),
          ),
          onTap: () => Navigator.of(context).pop(candidate),
        ),
      SimpleDialogOption(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
    ],
  );

  String _price(VariantePorCodigoBarras candidate) {
    final price = SaleDraftDisplay.money(candidate.precioVentaMenor);
    final unit = candidate.unidadVenta;
    final reference = candidate.saleConfiguration.priceReferenceQuantityAtomic;
    if (unit == null || reference == null) return price;
    return '$price / ${SaleDraftDisplay.measureNumber(reference, unit.factorAtomico)} ${unit.simbolo}';
  }
}
