import 'package:flutter/material.dart';

import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/ventas/measured_sale_calculator.dart';
import '../../../domain/ventas/measured_sale_conditions.dart';
import '../../../domain/ventas/sale_draft.dart';
import '../caja/models/sale_draft_display.dart';
import 'measured_sale_preview.dart';
import 'sale_quantity_form_result.dart';

class SaleQuantityDialog extends StatefulWidget {
  const SaleQuantityDialog({
    required this.loadConditions,
    required this.draft,
    super.key,
  });

  final Future<MeasuredSaleConditions?> Function() loadConditions;
  final Stream<SaleDraft?> draft;

  @override
  State<SaleQuantityDialog> createState() => _SaleQuantityDialogState();
}

class _SaleQuantityDialogState extends State<SaleQuantityDialog> {
  final _amount = TextEditingController();
  final _quantity = TextEditingController();
  late final _conditions = widget.loadConditions();
  static const _codec = InventoryQuantityCodec();
  static const _calculator = MeasuredSaleCalculator();
  static const _preview = MeasuredSalePreview();
  bool _fromAmount = true;
  bool _submitted = false;
  int _editRevision = 0;
  int? _atomic;
  int? _target;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _quantity.dispose();
    super.dispose();
  }

  int _parseAmount(String input) {
    final text = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Ingresa un importe con hasta dos decimales.',
      );
    }
    final parts = text.split('.');
    final minor =
        BigInt.parse(parts.first) * BigInt.from(100) +
        BigInt.parse(parts.length == 1 ? '0' : parts.last.padRight(2, '0'));
    if (minor <= BigInt.zero ||
        minor > BigInt.from(MeasuredSaleCalculator.maxInteger)) {
      throw const FormatException(
        'El importe debe ser positivo y estar dentro del límite permitido.',
      );
    }
    return minor.toInt();
  }

  void _edit(MeasuredSaleConditions conditions, {required bool fromAmount}) {
    setState(() {
      _editRevision++;
      _fromAmount = fromAmount;
      _atomic = null;
      _target = null;
      _error = null;
      try {
        final int atomic;
        if (fromAmount) {
          final target = _parseAmount(_amount.text);
          atomic = _calculator.quantityAtomicForAmount(
            targetAmountMinor: target,
            unitPriceMinor: conditions.unitPriceMinor,
            priceReferenceQuantityAtomic:
                conditions.priceReferenceQuantityAtomic,
          );
          _target = target;
          _quantity.text = _codec.formatAtomic(atomic, conditions.unit);
        } else {
          atomic = _codec.parsePositiveAtomic(_quantity.text, conditions.unit);
          final total = _calculator.totalMinor(
            unitPriceMinor: conditions.unitPriceMinor,
            quantityAtomic: atomic,
            priceReferenceQuantityAtomic:
                conditions.priceReferenceQuantityAtomic,
          );
          _amount.text = SaleDraftDisplay.money(total).substring(1);
        }
        // Valida también el total de la captura manual antes de habilitarla.
        _preview.capture(conditions, atomic);
        _atomic = atomic;
      } on FormatException catch (error) {
        _error = error.message;
        if (fromAmount) {
          _quantity.clear();
        } else {
          _amount.clear();
        }
      }
    });
  }

  void _submit(
    MeasuredSaleConditions conditions,
    bool valid,
    int reviewedRevision,
  ) {
    if (!valid ||
        _submitted ||
        _atomic == null ||
        reviewedRevision != _editRevision) {
      return;
    }
    setState(() => _submitted = true);
    Navigator.of(context).pop(
      SaleQuantityFormResult(
        measuredQuantity: _fromAmount ? null : _quantity.text.trim(),
        targetAmountMinor: _fromAmount ? _target : null,
        expectedUnitId: conditions.unit.id,
        expectedUnitPriceMinor: conditions.unitPriceMinor,
        expectedPriceReferenceQuantityAtomic:
            conditions.priceReferenceQuantityAtomic,
        displayQuantity: _codec.formatAtomic(_atomic!, conditions.unit),
        displayUnitSymbol: conditions.unit.simbolo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<SaleDraft?>(
    stream: widget.draft,
    builder: (context, draft) => FutureBuilder<MeasuredSaleConditions?>(
      future: _conditions,
      builder: (context, snapshot) {
        final conditions = snapshot.data;
        if (conditions == null) {
          return AlertDialog(
            title: const Text('Venta a granel'),
            content: snapshot.connectionState == ConnectionState.waiting
                ? const SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const Text(
                    'El artículo o su unidad ya no están disponibles. Vuelve a seleccionarlo.',
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ],
          );
        }
        String? previewError;
        int? total;
        String? accumulated;
        if (_atomic case final atomic?) {
          try {
            final capture = _preview.capture(conditions, atomic);
            total = capture.totalMinor;
            final line = _preview.accumulated(capture, draft.data);
            if (line != null) {
              accumulated =
                  'Línea acumulada prevista: '
                  '${_codec.formatAtomic(line.measuredQuantityAtomic!, conditions.unit)} '
                  '${conditions.unit.simbolo} · ${SaleDraftDisplay.money(line.totalMinor)}';
            }
          } on FormatException catch (error) {
            previewError = error.message;
            total = null;
          }
        }
        final valid =
            total != null &&
            previewError == null &&
            !draft.hasError &&
            draft.connectionState != ConnectionState.waiting &&
            !_submitted;
        // Una edición y Enter pueden llegar antes del siguiente frame. La
        // aceptación pertenece solo a la vista previa que ya se renderizó.
        final reviewedRevision = _editRevision;
        return AlertDialog(
          scrollable: true,
          title: Text(
            [
              conditions.productName,
              if (conditions.variantName != null) conditions.variantName!,
            ].join(' · '),
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Precio: ${SaleDraftDisplay.money(conditions.unitPriceMinor)} / '
                  '${_codec.formatAtomic(conditions.priceReferenceQuantityAtomic, conditions.unit)} '
                  '${conditions.unit.simbolo}',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('sale-target-amount'),
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _edit(conditions, fromAmount: true),
                  onSubmitted: (_) =>
                      _submit(conditions, valid, reviewedRevision),
                  decoration: InputDecoration(
                    labelText: 'Importe solicitado (\$)',
                    errorText: _fromAmount ? _error : null,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('sale-measured-quantity'),
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _edit(conditions, fromAmount: false),
                  onSubmitted: (_) =>
                      _submit(conditions, valid, reviewedRevision),
                  decoration: InputDecoration(
                    labelText: 'Cantidad (${conditions.unit.simbolo})',
                    errorText: !_fromAmount ? _error : null,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 16),
                if (total != null) ...[
                  Text(
                    'Cobro por esta cantidad: ${SaleDraftDisplay.money(total)}',
                  ),
                  if (_fromAmount && _target != null && total != _target)
                    Text(
                      'Ajuste por peso: +${SaleDraftDisplay.money(total - _target!)}',
                    ),
                  if (accumulated != null) Text(accumulated),
                ],
                if (previewError != null) Text(previewError),
                if (draft.hasError)
                  const Text(
                    'No se pudo revisar la acumulación. Vuelve a abrir el artículo.',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _submitted ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: valid
                  ? () => _submit(conditions, valid, reviewedRevision)
                  : null,
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    ),
  );
}
