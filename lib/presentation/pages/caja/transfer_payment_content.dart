import 'package:flutter/material.dart';

/// Contenido de cobro por transferencia dentro de la pantalla unificada.
class TransferPaymentContent extends StatefulWidget {
  const TransferPaymentContent({
    required this.processing,
    required this.enabled,
    required this.onConfirm,
    super.key,
  });

  final bool processing;

  /// Indica si la venta tiene los datos necesarios para confirmar.
  final bool enabled;

  final ValueChanged<String> onConfirm;

  @override
  State<TransferPaymentContent> createState() => _TransferPaymentContentState();
}

class _TransferPaymentContentState extends State<TransferPaymentContent> {
  final _reference = TextEditingController();
  final _form = GlobalKey<FormState>();

  void _confirm() {
    if (widget.processing || !_form.currentState!.validate()) return;
    widget.onConfirm(_reference.text);
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const Key('transfer_payment_content'),
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                key: const Key('transfer_reference_input'),
                controller: _reference,
                enabled: !widget.processing,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: widget.processing || !widget.enabled ? null : _confirm,
            child: Text(
              widget.processing ? 'Registrando…' : 'Confirmar transferencia',
            ),
          ),
        ),
      ],
    ),
  );
}
