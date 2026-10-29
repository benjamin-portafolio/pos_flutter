import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/sale_draft_display.dart';

/// Contenido de cobro en efectivo dentro de la pantalla unificada de pago.
class CashPaymentContent extends StatefulWidget {
  const CashPaymentContent({
    required this.totalMinor,
    required this.processing,
    required this.enabled,
    required this.enterArmed,
    required this.onConfirm,
    super.key,
  });

  final int totalMinor;
  final bool processing;

  /// Indica si la venta tiene los datos necesarios para confirmar.
  final bool enabled;

  /// Evita que el Enter que abrió el cobro confirme la venta por sí mismo.
  final bool enterArmed;

  /// `null` representa pago exacto, como el campo vacío actual.
  final ValueChanged<int?> onConfirm;

  @override
  State<CashPaymentContent> createState() => CashPaymentContentState();
}

class CashPaymentContentState extends State<CashPaymentContent> {
  final _received = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Efectivo recibido');

  BigInt get _receivedMinor {
    final parts = _received.text.replaceAll(',', '.').split('.');
    final whole = BigInt.parse(parts.first.isEmpty ? '0' : parts.first);
    final fraction = parts.length == 1 ? '00' : parts.last.padRight(2, '0');
    return whole * BigInt.from(100) + BigInt.parse(fraction);
  }

  bool get _outOfRange => _receivedMinor > BigInt.from(9007199254740991);

  bool get _pending =>
      _received.text.isNotEmpty &&
      _receivedMinor < BigInt.from(widget.totalMinor);

  bool get _canConfirm =>
      widget.enabled && !widget.processing && !_pending && !_outOfRange;

  int? get _receivedForCommand =>
      _received.text.isEmpty ? null : _receivedMinor.toInt();

  static String _amount(BigInt minor) =>
      '${minor ~/ BigInt.from(100)}.${minor.remainder(BigInt.from(100)).toString().padLeft(2, '0')}';

  void focusReceived() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.processing) _focus.requestFocus();
    });
  }

  void _addCash(int amount) {
    final text = _amount(_receivedMinor + BigInt.from(amount * 100));
    setState(() {
      _received.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  void _confirmFromButton() {
    if (!_canConfirm) return;
    widget.onConfirm(_receivedForCommand);
  }

  void _submitFromEnter() {
    if (!widget.enterArmed || widget.processing || !widget.enabled) return;
    if (_outOfRange) {
      _showMessage('El efectivo recibido excede el límite permitido.');
      return;
    }
    if (_pending) {
      _showMessage('El efectivo recibido es insuficiente.');
      return;
    }
    widget.onConfirm(_receivedForCommand);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _received.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vacío muestra el total como sugerencia y un cambio neutro, como el video.
    final difference = _received.text.isEmpty
        ? BigInt.zero
        : _receivedMinor - BigInt.from(widget.totalMinor);
    final pending = difference.isNegative;
    final label = pending
        ? 'Efectivo pendiente'
        : difference > BigInt.zero
        ? 'Cambio a dar'
        : 'Cambio';
    final color = pending
        ? Colors.orange.shade900
        : difference > BigInt.zero
        ? Colors.green.shade800
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const Key('cash_payment_content'),
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text(
                            'Efectivo recibido (opcional)',
                            textAlign: TextAlign.center,
                          ),
                          TextField(
                            key: const Key('cash_received_input'),
                            controller: _received,
                            focusNode: _focus,
                            enabled: !widget.processing,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineLarge,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) =>
                                    RegExp(
                                      r'^\d*(?:[.,]\d{0,2})?$',
                                    ).hasMatch(newValue.text)
                                    ? newValue
                                    : oldValue,
                              ),
                            ],
                            decoration: InputDecoration(
                              prefixText: '\$ ',
                              hintText: SaleDraftDisplay.money(
                                widget.totalMinor,
                              ).substring(1),
                              border: InputBorder.none,
                            ),
                            onChanged: (_) => setState(() {}),
                            // Conservar el foco tras validar o consumir el Enter
                            // de apertura para permitir una nueva pulsación.
                            onEditingComplete: () {},
                            onSubmitted: (_) => _submitFromEnter(),
                          ),
                        ],
                      ),
                    ),
                    ColoredBox(
                      color: pending
                          ? const Color(0xFFFFF8E1)
                          : difference > BigInt.zero
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFE8EAF6),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(label, style: TextStyle(color: color)),
                            const SizedBox(height: 8),
                            Text(
                              '${pending ? '-' : ''}\$${_amount(difference.abs())}',
                              textAlign: TextAlign.center,
                              style: Theme.of(
                                context,
                              ).textTheme.headlineLarge?.copyWith(color: color),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final amount in [20, 50, 100, 200, 500, 1000])
                    OutlinedButton(
                      onPressed: widget.processing
                          ? null
                          : () => _addCash(amount),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(100, 44),
                        backgroundColor: Colors.white,
                      ),
                      child: Text('+ \$$amount'),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _canConfirm ? _confirmFromButton : null,
            child: Text(
              widget.processing ? 'Registrando…' : 'Recibido por efectivo',
            ),
          ),
        ),
      ],
    );
  }
}
