import '../caja/models/sale_draft_display.dart';
import 'package:flutter/material.dart';
import '../../../application/sync/payloads/venta_confirmada_payload.dart';

/// Captura solo mercancía; importes y efectos los calcula aplicación.
class ReturnLinesForm extends StatefulWidget {
  const ReturnLinesForm({
    super.key,
    required this.original,
    required this.remaining,
    required this.onChanged,
    required this.enabled,
  });
  final VentaConfirmadaPayload original;
  final Map<String, int> remaining;
  final ValueChanged<Map<String, ({int quantity, String destination})>>
  onChanged;
  final bool enabled;
  @override
  State<ReturnLinesForm> createState() => _ReturnLinesFormState();
}

class _ReturnLinesFormState extends State<ReturnLinesForm> {
  final _quantities = <String, int>{};
  final _destinations = <String, String>{};
  void _change() => widget.onChanged({
    for (final e in _quantities.entries)
      if (e.value > 0)
        e.key: (
          quantity: e.value,
          destination: _destinations[e.key] ?? _default(e.key),
        ),
  });
  String _default(String id) => switch (widget.original.lines
      .singleWhere((l) => l.id == id)
      .consumptionMode) {
    'none' => 'untracked',
    'recipe' => 'not_restockable',
    _ => 'restock',
  };
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final l in widget.original.lines)
        if ((widget.remaining[l.id] ?? 0) > 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.snapshot.productName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Disponible: ${SaleDraftDisplay.measureNumber(widget.remaining[l.id]!, l.snapshot.unitAtomicFactor ?? 1)} ${l.snapshot.unitSymbol ?? 'pzas'}',
                  ),
                  TextFormField(
                    key: ValueKey('return-quantity-${l.id}'),
                    enabled: widget.enabled,
                    decoration: InputDecoration(
                      labelText:
                          'Cantidad (${l.snapshot.unitSymbol ?? 'pzas'})',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (value) {
                      // Decimal exacto: evita redondear silenciosamente cantidades capturadas.
                      final parts = value
                          .trim()
                          .replaceAll(',', '.')
                          .split('.');
                      int atomic = -1;
                      if (RegExp(
                        r'^\d+(\.\d+)?$',
                      ).hasMatch(value.trim().replaceAll(',', '.'))) {
                        final denominator = BigInt.from(
                          10,
                        ).pow(parts.length == 1 ? 0 : parts[1].length);
                        final numerator =
                            BigInt.parse(parts.join()) *
                            BigInt.from(l.snapshot.unitAtomicFactor ?? 1);
                        if (numerator % denominator == BigInt.zero &&
                            numerator ~/ denominator <=
                                BigInt.from(9007199254740991)) {
                          atomic = (numerator ~/ denominator).toInt();
                        }
                      }
                      _quantities[l.id] = value.trim().isEmpty ? 0 : atomic;
                      _change();
                    },
                    validator: (_) =>
                        (_quantities[l.id] ?? 0) < 0 ||
                            (_quantities[l.id] ?? 0) > widget.remaining[l.id]!
                        ? 'Usa una cantidad exacta dentro del remanente.'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _default(l.id),
                    decoration: const InputDecoration(
                      labelText: 'Destino de mercancía',
                    ),
                    items: [
                      if (l.consumptionMode == 'direct')
                        const DropdownMenuItem(
                          value: 'restock',
                          child: Text('Reintegrar a existencias'),
                        ),
                      if (l.consumptionMode != 'none')
                        const DropdownMenuItem(
                          value: 'not_restockable',
                          child: Text('No reintegrable'),
                        ),
                      if (l.consumptionMode == 'none')
                        const DropdownMenuItem(
                          value: 'untracked',
                          child: Text('Sin seguimiento'),
                        ),
                    ],
                    onChanged: !widget.enabled
                        ? null
                        : (v) {
                            _destinations[l.id] = v!;
                            _change();
                          },
                  ),
                  if (l.consumptionMode == 'recipe')
                    const Text(
                      'Producto elaborado: no se recuperan ingredientes.',
                    ),
                ],
              ),
            ),
          ),
    ],
  );
}
