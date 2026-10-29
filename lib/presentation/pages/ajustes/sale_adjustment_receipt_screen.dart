import '../caja/sale_receipt_screen.dart';
import 'sale_incident_action.dart';
import '../caja/models/sale_draft_display.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../application/tickets/ticket_document.dart';
import '../../../domain/repositories/sale_adjustment_repository.dart';
import '../../../domain/ventas/adjusted_sale.dart';
import '../../../domain/ventas/sale_adjustment_document.dart';
import '../../tickets/ticket_image_generator.dart';
import '../../tickets/ticket_print_action.dart';
import '../informes/models/report_money.dart';

/// Solo consulta y salida de documentos: reintentar compartir/imprimir nunca
/// vuelve a ejecutar un comando comercial.
class SaleAdjustmentReceiptScreen extends StatelessWidget {
  const SaleAdjustmentReceiptScreen({
    super.key,
    required this.operationId,
    required this.repository,
  });
  final String operationId;
  final SaleAdjustmentRepository repository;
  static String deliveryLabel(SaleAdjustmentDocument a) =>
      a.resolutionEventId != null
      ? 'Incidencia conciliada'
      : switch (a.deliveryStatus) {
          'delivered' => 'Aceptada por servidor',
          'not_required' => 'Registro local',
          'pending' => 'Pendiente de sincronizar',
          _ => 'Requiere atención: ${a.deliveryStatus}',
        };
  static TicketDocument ticket(
    AdjustedSale sale,
    SaleAdjustmentDocument a,
  ) => TicketDocument(
    title: a.settlementAction == 'unreceived_correction'
        ? 'CORRECCIÓN DE COBRO NO RECIBIDO'
        : a.lines.every((l) => l.destination == 'void')
        ? 'ANULACIÓN POR ERROR'
        : 'DEVOLUCIÓN',
    identifier: a.operationId,
    date: '${a.businessDate} · ${a.occurredAt.toLocal()}',
    currency: sale.original.currency,
    details: [
      'Venta original: ${a.saleId}',
      'Motivo: ${a.reason}',
      'Operador: ${a.userId} · Terminal: ${a.deviceId}',
      'Entrega: ${deliveryLabel(a)}',
      if (a.incidentId != null) 'Incidencia pendiente: ${a.incidentId}',
      if (a.resolutionEventId != null)
        'Conciliación: ${a.resolutionEventId} · Entrega original: ${a.deliveryStatus}',
      'Liquidación: ${switch (a.settlementAction) {
        'unreceived_correction' => 'Cobro no recibido',
        'credit_reduction' => 'Reducción de cargo',
        'no_money' => 'Sin movimiento de dinero',
        _ => 'Reembolso realizado',
      }} · ${switch (a.method) {
        'cash' => 'Efectivo',
        'credit' => 'Crédito',
        _ => 'Transferencia',
      }}',
      if (a.settlementReference != null) 'Referencia: ${a.settlementReference}',
      if (a.cashSessionId != null) 'Caja actual del ajuste: ${a.cashSessionId}',
    ],
    itemRows: [
      for (final l in a.lines)
        [
          sale.original.items
              .singleWhere((i) => i.id == l.saleItemId)
              .productName,
          switch (l.destination) {
            'void' => 'Restitución histórica',
            'restock' => 'Reintegrable',
            'not_restockable' => 'No reintegrable',
            _ => 'Sin seguimiento',
          },
          '${SaleDraftDisplay.measureNumber(l.quantityAtomic, sale.original.items.singleWhere((i) => i.id == l.saleItemId).unitAtomicFactor ?? 1)} ${sale.original.items.singleWhere((i) => i.id == l.saleItemId).unitSymbol ?? 'pzas'}',
          ReportMoney.money(BigInt.from(l.amountMinor)),
        ],
    ],
    totals: [
      (
        a.method == 'credit' ? 'Reducción de cargo' : 'Importe',
        ReportMoney.money(BigInt.from(a.amountMinor)),
      ),
    ],
    footer: 'Documento vinculado. Se conserva el ticket original.',
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Comprobante de ajuste')),
    body: StreamBuilder<List<AdjustedSale>>(
      stream: repository.watchSales(),
      builder: (context, s) {
        if (s.hasError) {
          return const Center(
            child: Text('No se pudo consultar el comprobante.'),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final sale = s.data!
            .where(
              (x) => x.adjustments.any((a) => a.operationId == operationId),
            )
            .firstOrNull;
        if (sale == null) {
          return const Center(child: Text('No se encontró el ajuste.'));
        }
        final a = sale.adjustments.singleWhere(
          (a) => a.operationId == operationId,
        );
        final document = ticket(sale, a);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              document.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SelectableText(document.identifier),
            Text(document.date),
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SaleReceiptScreen(
                    saleId: a.saleId,
                    returnButtonLabel: 'Volver al ajuste',
                  ),
                ),
              ),
              child: const Text('Ver ticket original'),
            ),
            if (a.incidentId != null)
              SaleIncidentAction(incidentId: a.incidentId!),
            for (final d in document.details) Text(d),
            const Divider(),
            for (final row in document.itemRows)
              ListTile(
                title: Text(row[0]),
                subtitle: Text('${row[1]} · ${row[2]}'),
                trailing: Text(row[3]),
              ),
            for (final t in document.totals)
              ListTile(title: Text(t.$1), trailing: Text(t.$2)),
            TicketPrintAction(document: document),
            Builder(
              builder: (context) => TextButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Compartir comprobante'),
                onPressed: () async {
                  final box = context.findRenderObject() as RenderBox;
                  final origin = box.localToGlobal(Offset.zero) & box.size;
                  try {
                    final bytes = await TicketImageGenerator().generate(
                      document,
                    );
                    await SharePlus.instance.share(
                      ShareParams(
                        files: [XFile.fromData(bytes, mimeType: 'image/png')],
                        fileNameOverrides: ['ajuste-$operationId.png'],
                        sharePositionOrigin: origin,
                      ),
                    );
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No se pudo compartir. Puedes reintentar.',
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
