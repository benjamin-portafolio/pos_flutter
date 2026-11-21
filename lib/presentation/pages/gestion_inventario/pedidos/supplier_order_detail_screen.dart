import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/di/injection.dart';
import '../../../../application/proveedores/supplier_order_reader.dart';
import '../../../../application/proveedores/supplier_order_detail.dart';
import '../../../../application/commands/proveedores/supplier_order_command_service.dart';
import '../../../../application/commands/proveedores/close_supplier_order_command.dart';
import '../../../../application/commands/proveedores/cancel_supplier_order_command.dart';
import '../../../../application/sync/payloads/supplier_order_closed_payload.dart';
import '../../../../application/tickets/supplier_document_ticket.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import 'supplier_order_forms.dart';
import 'supplier_receipt_screen.dart';
import 'supplier_document_screen.dart';

class SupplierOrderDetailScreen extends StatefulWidget {
  const SupplierOrderDetailScreen({required this.orderId, super.key});
  final String orderId;
  @override
  State<SupplierOrderDetailScreen> createState() =>
      _SupplierOrderDetailScreenState();
}

class _SupplierOrderDetailScreenState extends State<SupplierOrderDetailScreen> {
  late final stream = getIt<SupplierOrderReader>().watchDetail(widget.orderId);
  bool busy = false;
  String? message;
  Future<void> _finish(SupplierOrderDetail d, {required bool close}) async {
    if (busy) return;
    final lines = d.order.document.items.where((l) => d.pending(l) > 0);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(close ? 'Cerrar faltantes' : 'Cancelar pedido'),
        content: SingleChildScrollView(
          child: Text(
            close
                ? 'Estas cantidades dejan de esperarse. No se modifica inventario:\n${lines.map((l) => '${l.productNameSnapshot}: ${const InventoryQuantityCodec().formatAtomic(d.pending(l), lineUnit(l))} ${l.unitSymbolSnapshot}').join('\n')}'
                : 'Cancelar este pedido sin recepciones libera sus pendientes y conserva el documento.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(close ? 'Confirmar cierre' : 'Confirmar cancelación'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      final service = getIt<SupplierOrderCommandService>();
      if (close) {
        await service.closeRemainder(
          CloseSupplierOrderCommand(
            eventId: const Uuid().v4(),
            payload: SupplierOrderClosedPayload.fromJson({
              'contract_version': 1,
              'order_id': d.order.id,
              'base_event_id': d.order.lastEventId!,
              'occurred_at_ms': DateTime.now().millisecondsSinceEpoch,
              'items': [
                for (final l in lines)
                  {
                    'order_item_id': l.id,
                    'closed_quantity_atomic': d.pending(l),
                  },
              ],
            }),
          ),
        );
      } else {
        await service.cancel(
          CancelSupplierOrderCommand(
            eventId: const Uuid().v4(),
            orderId: d.order.id,
            baseEventId: d.order.lastEventId!,
            occurredAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalle del pedido')),
    body: StreamBuilder<SupplierOrderDetail?>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('No se pudo cargar el documento: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return Center(
            child: Text(
              snapshot.connectionState == ConnectionState.waiting
                  ? 'Cargando…'
                  : 'Pedido no disponible. Consulta los conflictos del listado.',
            ),
          );
        }
        final d = snapshot.data!, doc = d.order.document;
        final open = ['confirmed', 'partial'].contains(d.order.status);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              doc.supplierNameSnapshot,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Pedido ${doc.orderId}\nEstado: ${d.order.status}\n${deliveryLabel(d.deliveryStatus)}',
            ),
            if (doc.notes != null) Text(doc.notes!),
            if (message != null) Text(message!),
            for (final failure in d.failures)
              Text(
                failure,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              'Importe original estimado: ${orderMoney(doc.totalMinor)} ${doc.currency}\nImporte acumulado recibido: ${orderMoney(d.receivedTotal)} ${doc.currency}',
            ),
            for (final r in d.failedReceipts)
              OutlinedButton(
                onPressed: busy || !open
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SupplierReceiptScreen(initial: d, source: r),
                        ),
                      ),
                child: Text('Revisar intención rechazada ${r.receiptId}'),
              ),
            for (final l in doc.items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${l.productNameSnapshot} ${l.variantNameSnapshot ?? ''}\nPedido: ${const InventoryQuantityCodec().formatAtomic(l.quantityAtomic, lineUnit(l))} ${l.unitSymbolSnapshot}\nRecibido: ${const InventoryQuantityCodec().formatAtomic(d.received[l.id] ?? 0, lineUnit(l))} ${l.unitSymbolSnapshot}\nFaltantes cerrados: ${const InventoryQuantityCodec().formatAtomic(d.closed[l.id] ?? 0, lineUnit(l))} ${l.unitSymbolSnapshot}\nPendiente: ${const InventoryQuantityCodec().formatAtomic(d.pending(l), lineUnit(l))} ${l.unitSymbolSnapshot}\nPrecio pedido: ${orderMoney(l.quotedPriceMinor)} por ${const InventoryQuantityCodec().formatAtomic(l.referenceQuantityAtomic, lineUnit(l))} ${l.unitSymbolSnapshot}\nImporte pedido: ${orderMoney(l.totalMinor)} ${doc.currency}',
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SupplierDocumentScreen(
                    document: SupplierDocumentTicket.build(d),
                  ),
                ),
              ),
              child: const Text('Ticket del pedido'),
            ),
            if (open) ...[
              FilledButton(
                onPressed: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupplierReceiptScreen(initial: d),
                        ),
                      ),
                child: const Text('Recibir mercancía'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupplierReceiptScreen(
                            initial: d,
                            conforming: true,
                          ),
                        ),
                      ),
                child: const Text('Llegó conforme'),
              ),
            ],
            if (d.order.status == 'partial')
              TextButton(
                onPressed: busy ? null : () => _finish(d, close: true),
                child: const Text('Cerrar faltantes'),
              ),
            if (d.order.status == 'confirmed' && d.receipts.isEmpty)
              TextButton(
                onPressed: busy ? null : () => _finish(d, close: false),
                child: const Text('Cancelar pedido'),
              ),
            const Text('Recepciones vinculadas · documentos inmutables'),
            for (final r in d.receipts)
              Card(
                child: ExpansionTile(
                  key: ValueKey(r.receiptId),
                  title: Text('Recepción ${r.receiptId}'),
                  subtitle: Text(
                    '${DateTime.fromMillisecondsSinceEpoch(r.occurredAtMs).toLocal()}\nImporte real: ${orderMoney(r.totalMinor)} ${doc.currency}\n${deliveryLabel(d.receiptStatuses[r.receiptId] ?? 'pending')}',
                  ),
                  children: [
                    for (final i in r.items)
                      Builder(
                        builder: (context) {
                          final l = doc.items.singleWhere(
                            (l) => l.id == i.orderItemId,
                          );
                          return ListTile(
                            title: Text(
                              '${l.productNameSnapshot} ${l.variantNameSnapshot ?? ''}',
                            ),
                            subtitle: Text(
                              '${const InventoryQuantityCodec().formatAtomic(i.quantityAtomic, lineUnit(l))} ${l.unitSymbolSnapshot} · Precio real ${orderMoney(i.actualPriceMinor)} por ${const InventoryQuantityCodec().formatAtomic(l.referenceQuantityAtomic, lineUnit(l))} ${l.unitSymbolSnapshot}\nImporte: ${orderMoney(i.totalMinor)} ${doc.currency}${i.overageAcknowledged ? ' · Exceso revisado' : ''}',
                            ),
                          );
                        },
                      ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupplierDocumentScreen(
                            document: SupplierDocumentTicket.build(
                              d,
                              receipt: r,
                            ),
                            initialStatus: d.receiptStatuses[r.receiptId],
                            statusUpdates: getIt<SupplierOrderReader>()
                                .watchDetail(widget.orderId)
                                .map(
                                  (current) =>
                                      current?.receiptStatuses[r.receiptId] ??
                                      'rejected',
                                ),
                          ),
                        ),
                      ),
                      child: const Text('Ticket de recepción'),
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
