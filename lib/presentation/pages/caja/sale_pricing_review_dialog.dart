import 'package:flutter/material.dart';

import '../../../application/sync/payloads/tarifa_venta_borrador_cambiada_payload.dart';
import 'models/sale_draft_display.dart';

/// Revisión N2 calculada por el motor; confirmar conserva su intención y base.
class SalePricingReviewDialog extends StatelessWidget {
  const SalePricingReviewDialog({required this.preview, super.key});

  final TarifaVentaBorradorCambiadaPayload preview;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      preview.pricingMode == 'offer'
          ? 'Activar precio de oferta'
          : 'Volver a precio normal',
    ),
    scrollable: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tarifa actual: ${preview.previousMode == 'offer' ? 'Oferta' : 'Normal'}',
        ),
        Text(
          'Tarifa nueva: ${preview.pricingMode == 'offer' ? 'Oferta' : 'Normal'}',
        ),
        const SizedBox(height: 8),
        Text(
          '${preview.amountChangedLines} ${preview.amountChangedLines == 1 ? 'línea cambia' : 'líneas cambian'} de importe.',
        ),
        if (preview.sourceOnlyChangedLines > 0)
          Text(
            '${preview.sourceOnlyChangedLines} ${preview.sourceOnlyChangedLines == 1 ? 'línea cambia' : 'líneas cambian'} de tarifa sin cambiar de importe.',
          ),
        Text(
          '${preview.withoutOfferLines} ${preview.withoutOfferLines == 1 ? 'línea sin oferta conserva' : 'líneas sin oferta conservan'} precio normal.',
        ),
        const SizedBox(height: 12),
        Text(
          'Total actual: ${SaleDraftDisplay.money(preview.previousTotalMinor)}',
        ),
        Text(
          'Nuevo total: ${SaleDraftDisplay.money(preview.totalMinor)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Se conserva la cantidad física, también en capturas por importe. '
          'Los próximos productos usarán la tarifa seleccionada.',
        ),
        if (preview.pricingMode == 'normal')
          const Text('Se restaura el precio normal capturado en cada línea.'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('confirm_sale_pricing'),
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Confirmar cambio'),
      ),
    ],
  );
}
