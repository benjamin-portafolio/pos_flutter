import 'package:flutter/material.dart';

import 'cash_payment_screen.dart';

class PaymentMethodScreen extends StatelessWidget {
  const PaymentMethodScreen({required this.totalMinor, super.key});

  final int totalMinor;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cobrar')),
    backgroundColor: const Color(0xFFF0F0F0),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'DETALLES DEL CLIENTE (OPCIONAL)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 12),
          const _CustomerDetails(),
          const SizedBox(height: 24),
          Text(
            'Seleccione el método de pago',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final method in [
                      ('Efectivo', Icons.payments_outlined),
                      ('Tarjeta de débito', Icons.credit_card),
                      ('Tarjeta de crédito', Icons.credit_card_outlined),
                      (
                        'Transferencia bancaria',
                        Icons.account_balance_outlined,
                      ),
                    ])
                      SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: OutlinedButton(
                          onPressed: method.$1 == 'Efectivo'
                              ? () => Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => CashPaymentScreen(
                                      totalMinor: totalMinor,
                                    ),
                                  ),
                                )
                              : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 20,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(method.$2, size: 40),
                              const SizedBox(height: 12),
                              Text(method.$1, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// Los datos del cliente quedan visibles hasta implementar su propio flujo.
class _CustomerDetails extends StatelessWidget {
  const _CustomerDetails();

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: TextField(
                  enabled: false,
                  decoration: InputDecoration(hintText: '+52'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    hintText: 'Número de teléfono móvil',
                  ),
                ),
              ),
              IconButton(
                onPressed: null,
                tooltip: 'Buscar cliente',
                icon: Icon(Icons.search),
              ),
            ],
          ),
          SizedBox(height: 12),
          TextField(
            enabled: false,
            decoration: InputDecoration(labelText: 'Nombre del cliente'),
          ),
          IconButton(
            onPressed: null,
            tooltip: 'Más datos del cliente',
            icon: Icon(Icons.arrow_drop_down),
          ),
        ],
      ),
    ),
  );
}
