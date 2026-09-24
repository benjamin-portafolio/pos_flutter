import 'package:flutter/material.dart';
import '../../../domain/cobros/collection_entry.dart';
import '../caja/models/sale_draft_display.dart';
import '../caja/sale_receipt_screen.dart';
import 'models/report_period.dart';

class CollectionMovementsScreen extends StatelessWidget {
  const CollectionMovementsScreen({
    super.key,
    required this.collections,
    required this.period,
    required this.initialEntries,
    this.method,
  });
  final Stream<List<CollectionEntry>> collections;
  final ReportPeriod period;
  final List<CollectionEntry> initialEntries;
  final String? method;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (method) {
        'cash' => 'Cobros en efectivo',
        'transfer' => 'Cobros por transferencia',
        _ => 'Cobros recibidos',
      }),
    ),
    body: StreamBuilder<List<CollectionEntry>>(
      stream: collections,
      initialData: initialEntries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('No se pudieron cargar los cobros.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!
            .where(
              (e) =>
                  period.contains(e.date) &&
                  (method == null || e.method == method),
            )
            .toList();
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(period.label),
            ),
            if (entries.isEmpty)
              const ListTile(title: Text('Sin cobros en este período')),
            for (final e in entries)
              Card(
                child: ExpansionTile(
                  title: Text(
                    '${SaleDraftDisplay.money(e.amountMinor)} MXN · ${e.method == 'cash' ? 'Efectivo' : 'Transferencia'}',
                  ),
                  subtitle: Text(
                    '${e.origin == 'sale' ? 'Pago de venta' : 'Abono / anticipo'} · ${e.date.toLocal()}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            [
                              'Pago: ${e.id}',
                              if (e.reference != null)
                                'Referencia: ${e.reference}',
                              if (e.saleId != null) 'Venta: ${e.saleId}',
                              if (e.clienteId != null)
                                'Cliente: ${e.clienteNombre ?? ''} (${e.clienteId})',
                              'Usuario: ${e.userId}',
                              'Dispositivo: ${e.deviceId}',
                              'Evento: ${e.eventId}',
                              'Entrega: ${switch (e.deliveryStatus) {
                                'not_required' => 'Registro local',
                                'pending' => 'Pendiente de sincronizar',
                                'delivered' => 'Sincronizada',
                                _ => 'Requiere atención',
                              }}',
                              if (e.reason != null) 'Motivo: ${e.reason}',
                            ].join('\n'),
                          ),
                          if (e.saleId != null)
                            TextButton(
                              onPressed: () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SaleReceiptScreen(saleId: e.saleId!),
                                ),
                              ),
                              child: const Text('Ver venta'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}
