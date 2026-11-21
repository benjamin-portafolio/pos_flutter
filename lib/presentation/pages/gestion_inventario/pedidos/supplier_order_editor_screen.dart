import 'supplier_order_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/di/injection.dart';
import '../../../../application/sync/projections/supplier_order_projection.dart';
import '../../../../application/sync/projections/supplier_order_projection_store.dart';
import '../../../../application/sync/payloads/supplier_order_line.dart';
import '../../../../application/sync/payloads/supplier_order_json.dart';
import '../../../../application/commands/proveedores/supplier_order_command_service.dart';
import '../../../../application/commands/proveedores/save_supplier_order_command.dart';
import '../../../../application/commands/proveedores/cancel_supplier_order_command.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import 'supplier_order_forms.dart';
import 'supplier_order_line_dialog.dart';

class SupplierOrderEditorScreen extends StatefulWidget {
  const SupplierOrderEditorScreen({required this.orderId, super.key});
  final String orderId;
  @override
  State<SupplierOrderEditorScreen> createState() =>
      _SupplierOrderEditorScreenState();
}

class _SupplierOrderEditorScreenState extends State<SupplierOrderEditorScreen> {
  final store = getIt<SupplierOrderProjectionStore>();
  final service = getIt<SupplierOrderCommandService>();
  final notes = TextEditingController();
  SupplierOrderProjection? order;
  List<SupplierOrderLine> items = [];
  Map<String, String> basis = {};
  bool busy = false, dirty = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await store.find(widget.orderId);
      final catalog = await store.candidates();
      if (!mounted) return;
      setState(() {
        order = result;
        error = result == null
            ? 'El pedido ya no está proyectado. Consulta los conflictos de sincronización para recuperar la intención.'
            : null;
        dirty = false;
        items = [...?result?.document.items];
        notes.text = result?.document.notes ?? '';
        basis = {
          for (final c in catalog.where(
            (c) => c.supplierId == result?.document.supplierId,
          ))
            c.variantId: c.basis,
        };
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _refreshBase() async {
    final current = await store.find(widget.orderId);
    if (!mounted) return;
    if (current == null || current.status != 'draft') {
      setState(
        () => error =
            'El pedido dejó de ser borrador. Puedes consultar la versión vigente al volver al listado. Se conserva esta captura hasta que salgas.',
      );
      return;
    }
    setState(() {
      order = current;
      basis = {};
      error =
          'Base recuperada. Tus cantidades, precios y notas se conservan; revísalos antes de confirmar.';
    });
  }

  Future<void> _save({bool confirm = false, bool close = false}) async {
    if (busy || order == null) return;
    setState(() => busy = true);
    try {
      final o = order!;
      final doc = orderDocument(
        id: o.id,
        base: o.lastEventId,
        supplierId: o.document.supplierId,
        name: o.document.supplierNameSnapshot,
        phone: o.document.supplierPhoneSnapshot,
        currency: o.document.currency,
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        items: items,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      await service.save(
        SaveSupplierOrderCommand(
          eventId: const Uuid().v4(),
          document: doc,
          catalogBasis: basis,
          confirm: confirm,
        ),
      );
      final result = await store.find(o.id);
      if (!mounted) return;
      setState(() {
        order = result;
        dirty = false;
        error = null;
      });
      if (close) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _review() async {
    try {
      final catalog = await store.candidates();
      final next = {
        for (final c in catalog.where(
          (c) => c.supplierId == order!.document.supplierId,
        ))
          c.variantId: c.basis,
      };
      if (!mounted) return;
      final changed = items.any((l) => basis[l.variantId] != next[l.variantId]);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Revisar pedido'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (changed)
                  const Text(
                    'Cambió la base conocida. Se conservan tus cantidades y precios. Revisa los datos vigentes antes de confirmar.',
                  ),
                for (final l in items) ...[
                  Text(
                    '${l.productNameSnapshot}: ${const InventoryQuantityCodec().formatAtomic(l.quantityAtomic, lineUnit(l))} ${l.unitSymbolSnapshot} · ${orderMoney(l.quotedPriceMinor)} por ${const InventoryQuantityCodec().formatAtomic(l.referenceQuantityAtomic, lineUnit(l))} ${l.unitSymbolSnapshot}',
                  ),
                  ...catalog
                      .where(
                        (c) =>
                            c.variantId == l.variantId &&
                            c.supplierId == order!.document.supplierId,
                      )
                      .map(
                        (c) => Text(
                          'Vigente: saldo ${c.balanceAtomic}, pendiente ${c.pendingAtomic}, objetivo ${c.targetAtomic ?? 'sin objetivo'} átomos; cotización ${orderMoney(c.priceMinor)}; proveedor actual ${c.currentSupplierId ?? 'sin selección'}',
                        ),
                      ),
                ],
                Text(
                  'Estimado: ${orderMoney(orderTotal(items.map((l) => l.totalMinor)))} ${order!.document.currency}',
                ),
                const Text(
                  'Confirmar congela el documento. No cambia existencias.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar pedido'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        basis = next;
        await _save(confirm: true);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _add() async {
    try {
      final candidates = (await store.candidates())
          .where(
            (c) =>
                c.supplierId == order!.document.supplierId &&
                !items.any((l) => l.variantId == c.variantId),
          )
          .toList();
      if (!mounted) return;
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Agregar variante del proveedor'),
          children: [
            for (var i = 0; i < candidates.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, i),
                child: Text(
                  '${candidates[i].productName} ${candidates[i].variantName ?? ''}',
                ),
              ),
          ],
        ),
      );
      if (selected == null) return;
      final c = candidates[selected];
      setState(() {
        items.add(candidateLine(c, const Uuid().v4(), c.atomicFactor));
        basis[c.variantId] = c.basis;
        dirty = true;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _cancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: const Text(
          'Se conservará en el historial y dejará de contar como pendiente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => busy = true);
    try {
      await service.cancel(
        CancelSupplierOrderCommand(
          eventId: const Uuid().v4(),
          orderId: order!.id,
          baseEventId: order!.lastEventId!,
          occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _load();
      dirty = false;
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final editable = o?.status == 'draft';
    return PopScope(
      canPop: !dirty && !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy) _save(close: true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            o == null
                ? 'Pedido'
                : '${o.document.supplierNameSnapshot} · ${o.status}',
          ),
        ),
        body: o == null
            ? Center(child: Text(error ?? 'Cargando pedido…'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (error != null && editable)
                    TextButton(
                      onPressed: busy ? null : _refreshBase,
                      child: const Text('Recuperar base y conservar captura'),
                    ),
                  Text('Pedido ${o.id}'),
                  Text(
                    'Estimado: ${orderMoney(orderTotal(items.map((l) => l.totalMinor)))} ${o.document.currency}',
                  ),
                  for (var i = 0; i < items.length; i++)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${items[i].productNameSnapshot} ${items[i].variantNameSnapshot ?? ''}',
                        ),
                        subtitle: Text(
                          '${const InventoryQuantityCodec().formatAtomic(items[i].quantityAtomic, lineUnit(items[i]))} ${items[i].unitSymbolSnapshot}\nPrecio: ${orderMoney(items[i].quotedPriceMinor)} por ${const InventoryQuantityCodec().formatAtomic(items[i].referenceQuantityAtomic, lineUnit(items[i]))} ${items[i].unitSymbolSnapshot} · Importe: ${orderMoney(items[i].totalMinor)}',
                        ),
                        onTap: !editable || busy
                            ? null
                            : () async {
                                final line =
                                    await showDialog<SupplierOrderLine>(
                                      context: context,
                                      builder: (_) => SupplierOrderLineDialog(
                                        line: items[i],
                                      ),
                                    );
                                if (line != null && mounted) {
                                  setState(() {
                                    items[i] = line;
                                    dirty = true;
                                  });
                                }
                              },
                        trailing: !editable
                            ? null
                            : IconButton(
                                tooltip: 'Quitar partida',
                                onPressed: busy || items.length == 1
                                    ? null
                                    : () => setState(() {
                                        items.removeAt(i);
                                        dirty = true;
                                      }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                      ),
                    ),
                  TextField(
                    controller: notes,
                    readOnly: !editable || busy,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notas'),
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                  if (editable) ...[
                    TextButton(
                      onPressed: busy || items.length >= 50 ? null : _add,
                      child: const Text('Agregar variante'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : () => _save(),
                      child: const Text('Guardar borrador'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : _review,
                      child: const Text('Revisar y confirmar'),
                    ),
                  ],
                  if (!editable)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SupplierOrderDetailScreen(orderId: o.id),
                              ),
                            ),
                      child: const Text('Ver detalle, recepciones y tickets'),
                    ),
                  if (o.status == 'draft')
                    TextButton(
                      onPressed: busy ? null : _cancel,
                      child: const Text('Cancelar pedido'),
                    ),
                ],
              ),
      ),
    );
  }
}
