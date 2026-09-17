import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import 'models/sale_draft_display.dart';

/// Consulta persistente del cobro, incluidas incidencias de entrega.
class ConfirmedSalesScreen extends StatefulWidget {
  const ConfirmedSalesScreen({this.saleId, super.key});
  final String? saleId;
  @override
  State<ConfirmedSalesScreen> createState() => _ConfirmedSalesScreenState();
}

class _ConfirmedSalesScreenState extends State<ConfirmedSalesScreen> {
  late final _sales = getIt<ConfirmedSaleRepository>().watchSales();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ventas cobradas')),
    body: StreamBuilder<List<ConfirmedSale>>(
      stream: _sales,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('No se pudieron cargar las ventas.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data!
            .where((e) => widget.saleId == null || e.id == widget.saleId)
            .toList();
        return ListView(children: [for (final e in events) _receipt(e)]);
      },
    ),
    bottomNavigationBar: widget.saleId == null
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Nueva venta'),
              ),
            ),
          ),
  );
  Widget _receipt(ConfirmedSale e) {
    final status = switch (e.deliveryStatus) {
      'delivered' => 'Sincronizada',
      'conflict' || 'rejected' => 'Requiere atención',
      'not_required' => 'Cobrada (registro local)',
      _ => 'Cobrada, pendiente de sincronizar',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status, style: Theme.of(context).textTheme.titleLarge),
            Text('Venta: ${e.id}'),
            Text('${e.createdAt.toLocal()}'),
            for (final l in e.items)
              Text(
                '${l.productName} ${l.variantName ?? ''} · ${SaleDraftDisplay.quantity(l)}${l.quantity == null ? '' : ' pza'} · ${SaleDraftDisplay.money(l.totalMinor)}',
              ),
            const Divider(),
            Text(
              'Pagado: ${SaleDraftDisplay.money(e.totalMinor)} ${e.currency}',
            ),
            Text('Recibido: ${SaleDraftDisplay.money(e.receivedMinor)}'),
            Text('Cambio: ${SaleDraftDisplay.money(e.changeMinor)}'),
            if (e.reason != null) Text(e.reason!),
          ],
        ),
      ),
    );
  }
}
