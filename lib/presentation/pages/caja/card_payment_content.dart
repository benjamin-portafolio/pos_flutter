import 'package:flutter/material.dart';

/// Pestaña informativa de tarjeta. No confirma ni registra pagos.
class CardPaymentContent extends StatelessWidget {
  const CardPaymentContent({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('card_payment_content'),
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.credit_card_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'El pago con tarjeta aún no está disponible',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'No se registrará ningún cobro desde esta pestaña.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
