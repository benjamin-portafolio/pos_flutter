import 'package:flutter/material.dart';

import '../../../domain/clientes/cliente.dart';

/// Contenido de cobro a crédito dentro de la pantalla unificada de pago.
class CreditPaymentContent extends StatelessWidget {
  const CreditPaymentContent({
    required this.cliente,
    required this.processing,
    required this.enabled,
    required this.onConfirm,
    super.key,
  });

  final Cliente? cliente;
  final bool processing;

  /// Exige cliente seleccionado y una venta confirmable.
  final bool enabled;

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ListView(
          key: const Key('credit_payment_content'),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente?.nombre ?? 'Sin cliente seleccionado',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (cliente != null) ...[
                      const SizedBox(height: 4),
                      Text(cliente!.telefono ?? 'Sin teléfono'),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'El total se cargará a la cuenta del cliente. '
                      'No se recibe efectivo en esta operación.',
                    ),
                    if (cliente == null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Selecciona un cliente para confirmar el crédito.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton(
          onPressed: processing || !enabled ? null : onConfirm,
          child: Text(processing ? 'Registrando…' : 'Confirmar crédito'),
        ),
      ),
    ],
  );
}
