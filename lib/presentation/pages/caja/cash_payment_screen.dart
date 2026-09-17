import '../../../application/commands/ventas/confirmar_venta_command.dart';
import '../../../application/commands/ventas/venta_command_service.dart';
import '../../../core/di/injection.dart';
import 'sale_receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/sale_draft_display.dart';

/// Confirma efectivo después del commit local.
class CashPaymentScreen extends StatefulWidget {
  const CashPaymentScreen({
    required this.totalMinor,
    this.saleId,
    this.expectedDraftEventId,
    this.commandService,
    super.key,
  });

  final int totalMinor;
  final String? saleId, expectedDraftEventId;
  final VentaCommandService? commandService;

  @override
  State<CashPaymentScreen> createState() => _CashPaymentScreenState();
}

class _CashPaymentScreenState extends State<CashPaymentScreen> {
  final _received = TextEditingController();
  bool _processing = false;
  Future<void> _confirm() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final received = _received.text.isEmpty ? null : _receivedMinor;
      if (received != null && received > BigInt.from(9007199254740991)) {
        throw const FormatException('Efectivo fuera de rango.');
      }
      await (widget.commandService ?? getIt<VentaCommandService>()).confirmar(
        ConfirmarVentaCommand(
          saleId: widget.saleId!,
          expectedDraftEventId: widget.expectedDraftEventId!,
          expectedTotalMinor: widget.totalMinor,
          receivedMinor: received?.toInt(),
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SaleReceiptScreen(saleId: widget.saleId!),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  BigInt get _receivedMinor {
    final parts = _received.text.replaceAll(',', '.').split('.');
    final whole = BigInt.parse(parts.first.isEmpty ? '0' : parts.first);
    final fraction = parts.length == 1 ? '00' : parts.last.padRight(2, '0');
    return whole * BigInt.from(100) + BigInt.parse(fraction);
  }

  static String _amount(BigInt minor) =>
      '${minor ~/ BigInt.from(100)}.${minor.remainder(BigInt.from(100)).toString().padLeft(2, '0')}';

  void _addCash(int amount) {
    final text = _amount(_receivedMinor + BigInt.from(amount * 100));
    setState(() {
      _received.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  @override
  void dispose() {
    _received.dispose();
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

    return Scaffold(
      appBar: AppBar(title: const Text('Efectivo')),
      backgroundColor: const Color(0xFFF0F0F0),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
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
                              Row(
                                children: [
                                  const Expanded(child: Text('Gran total')),
                                  Flexible(
                                    child: Text(
                                      SaleDraftDisplay.money(widget.totalMinor),
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              const Text(
                                'Efectivo recibido (opcional)',
                                textAlign: TextAlign.center,
                              ),
                              TextField(
                                controller: _received,
                                textAlign: TextAlign.center,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(color: color),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final amount in [20, 50, 100, 200, 500, 1000])
                        OutlinedButton(
                          onPressed: () => _addCash(amount),
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
                onPressed:
                    _processing ||
                        pending ||
                        widget.saleId == null ||
                        widget.expectedDraftEventId == null ||
                        _receivedMinor > BigInt.from(9007199254740991)
                    ? null
                    : _confirm,
                child: Text(
                  _processing ? 'Registrando…' : 'Recibido por efectivo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
