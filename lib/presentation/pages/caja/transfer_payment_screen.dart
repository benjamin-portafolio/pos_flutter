import 'package:flutter/material.dart';
import '../../../application/commands/ventas/confirmar_venta_command.dart';
import '../../../application/commands/ventas/venta_command_service.dart';
import '../../../core/di/injection.dart';
import 'models/sale_draft_display.dart';
import 'sale_receipt_screen.dart';

class TransferPaymentScreen extends StatefulWidget {
  const TransferPaymentScreen({
    super.key,
    required this.totalMinor,
    required this.saleId,
    required this.expectedDraftEventId,
    this.clienteId,
    this.commandService,
  });
  final int totalMinor;
  final String saleId, expectedDraftEventId;
  final String? clienteId;
  final VentaCommandService? commandService;
  @override
  State<TransferPaymentScreen> createState() => _TransferPaymentScreenState();
}

class _TransferPaymentScreenState extends State<TransferPaymentScreen> {
  final _reference = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _processing = false;
  Future<void> _confirm() async {
    if (_processing || !_form.currentState!.validate()) return;
    setState(() => _processing = true);
    try {
      await (widget.commandService ?? getIt<VentaCommandService>()).confirmar(
        ConfirmarVentaCommand(
          saleId: widget.saleId,
          expectedDraftEventId: widget.expectedDraftEventId,
          expectedTotalMinor: widget.totalMinor,
          clienteId: widget.clienteId,
          paymentMethod: 'transfer',
          paymentReference: _reference.text,
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SaleReceiptScreen(saleId: widget.saleId),
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

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_processing,
    child: Scaffold(
      appBar: AppBar(title: const Text('Transferencia bancaria')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Total a pagar'),
              Text(
                '${SaleDraftDisplay.money(widget.totalMinor)} MXN',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _reference,
                enabled: !_processing,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Referencia (opcional)',
                  helperText: 'Hasta 500 caracteres',
                ),
                validator: (value) => (value?.trim().length ?? 0) > 500
                    ? 'La referencia admite hasta 500 caracteres.'
                    : null,
              ),
              const SizedBox(height: 24),
              const Text(
                'Al confirmar, el total se registra como recibido por transferencia.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _processing ? null : _confirm,
                child: Text(
                  _processing ? 'Registrando…' : 'Confirmar transferencia',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
