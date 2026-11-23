import '../../../../application/sync/payloads/supplier_order_draft_saved_payload.dart';
import 'confirm_supplier_order_draft_deletion.dart';
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
import '../../../../domain/proveedores/replenishment_candidate.dart';
import 'supplier_order_forms.dart';
import 'supplier_order_line_dialog.dart';
import 'supplier_order_quantity_editor.dart';
import 'supplier_order_variant_search_screen.dart';

class SupplierOrderEditorScreen extends StatefulWidget {
  const SupplierOrderEditorScreen({
    required this.orderId,
    this.initialDocument,
    super.key,
  });
  final SupplierOrderDraftSavedPayload? initialDocument;
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
  String? editingId;
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
      final initial = widget.initialDocument;
      final result = initial == null
          ? await store.find(widget.orderId)
          : SupplierOrderProjection(
              document: initial,
              status: 'draft',
              version: 0,
              createdEventId: null,
              lastEventId: null,
              lastServerSequence: null,
            );
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

  Future<void> _save({bool confirm = false}) async {
    if (busy || order == null || editingId != null || items.isEmpty) return;
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
                  const Divider(),
                  Text(
                    [
                      l.productNameSnapshot,
                      if (l.variantNameSnapshot != null) l.variantNameSnapshot!,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('${_quantity(l, l.quantityAtomic)} × ${_price(l)}'),
                  Text('Importe: ${_money(l.totalMinor)}'),
                  ...catalog
                      .where(
                        (c) =>
                            c.variantId == l.variantId &&
                            c.supplierId == order!.document.supplierId,
                      )
                      .map(
                        (c) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Existencias: ${candidateQuantity(c, c.balanceAtomic)} ${c.unitSymbol} · Pendiente de recibir: ${candidateQuantity(c, c.pendingAtomic)} ${c.unitSymbol}',
                            ),
                            Text(
                              'Objetivo: ${c.targetAtomic == null ? 'Sin objetivo' : '${candidateQuantity(c, c.targetAtomic!)} ${c.unitSymbol}'}',
                            ),
                            Text(
                              'Precio vigente: ${_money(c.priceMinor)} por ${candidateQuantity(c, c.referenceAtomic)} ${c.unitSymbol}',
                            ),
                            if (!c.isCurrent)
                              const Text(
                                'Este proveedor ya no es el seleccionado para el producto.',
                              ),
                          ],
                        ),
                      ),
                ],
                const Divider(),
                Text(
                  'Total estimado: ${_money(orderTotal(items.map((l) => l.totalMinor)))} ${order!.document.currency}',
                ),
                if (items.any((l) => l.quotedPriceMinor == null))
                  const Text('Estimado incompleto: hay productos sin precio.'),
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
      final c = await Navigator.of(context).push<ReplenishmentCandidate>(
        MaterialPageRoute(
          builder: (_) => SupplierOrderVariantSearchScreen(
            supplierName: order!.document.supplierNameSnapshot,
            candidates: candidates,
          ),
        ),
      );
      if (c == null || !mounted) return;
      setState(() {
        items.add(candidateLine(c, const Uuid().v4(), c.atomicFactor));
        basis[c.variantId] = c.basis;
        dirty = true;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  String _quantity(SupplierOrderLine line, int value) =>
      '${const InventoryQuantityCodec().formatAtomic(value, lineUnit(line))} ${line.unitSymbolSnapshot}';
  String _money(int? value) =>
      value == null ? 'Sin precio' : '\$${orderMoney(value)}';
  String _price(SupplierOrderLine line) => line.quotedPriceMinor == null
      ? 'Sin precio'
      : '${_money(line.quotedPriceMinor)} por ${_quantity(line, line.referenceQuantityAtomic)}';

  Future<void> _editPrice(int index) async {
    final line = await showDialog<SupplierOrderLine>(
      context: context,
      builder: (_) => SupplierOrderLineDialog(line: items[index]),
    );
    if (line != null && mounted) {
      setState(() {
        items[index] = line;
        dirty = true;
      });
    }
  }

  void _deleteLine(int index) => setState(() {
    items.removeAt(index);
    editingId = null;
    dirty = true;
  });

  void _changeQuantity(int index, int delta) {
    final line = items[index];
    final quantity = line.quantityAtomic + delta;
    if (quantity == 0) {
      _deleteLine(index);
      return;
    }
    if (quantity < 0 || quantity > supplierOrderMaxInteger) return;
    try {
      final price = line.quotedPriceMinor;
      final next = SupplierOrderLine.fromJson({
        ...line.toJson(),
        'quantity_atomic': quantity,
        'total_minor': price == null
            ? null
            : orderAmount(price, quantity, line.referenceQuantityAtomic),
      });
      setState(() {
        items[index] = next;
        dirty = true;
      });
    } on FormatException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message.toString())));
    }
  }

  Future<void> _discardChanges() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salir sin guardar cambios'),
        content: Text(
          order?.lastEventId == null
              ? 'La preparación no se guardará y no se creará ningún borrador.'
              : 'Se conservará el último pedido guardado; los cambios de esta captura se descartarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir sin guardar'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => dirty = false);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteDraft() async {
    final current = order;
    if (busy || current == null || current.status != 'draft') return;
    setState(() => busy = true);
    try {
      if (!await confirmSupplierOrderDraftDeletion(
            context,
            current.document.supplierNameSnapshot,
          ) ||
          !mounted) {
        return;
      }
      await service.cancel(
        CancelSupplierOrderCommand(
          eventId: const Uuid().v4(),
          orderId: current.id,
          baseEventId: current.lastEventId!,
          occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      setState(() {
        dirty = false;
        busy = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => error = 'No se pudo eliminar el borrador: $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final editable = o?.status == 'draft';
    return PopScope(
      canPop: !dirty && !busy && editingId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy) {
          if (editingId != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Pulsa Listo para terminar de editar la cantidad.',
                ),
              ),
            );
          } else {
            _discardChanges();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(o == null ? 'Pedido' : o.document.supplierNameSnapshot),
        ),
        bottomNavigationBar: o == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${items.length} partidas · Total estimado: ${_money(orderTotal(items.map((l) => l.totalMinor)))} ${o.document.currency}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (items.any((l) => l.quotedPriceMinor == null))
                        const Text(
                          'Estimado incompleto: hay productos sin precio.',
                        ),
                      if (editable) ...[
                        if (o.lastEventId == null)
                          const Text(
                            'Guarda el pedido antes de revisarlo y confirmarlo.',
                          ),
                        if (editingId != null)
                          const Text(
                            'Pulsa Listo para terminar de editar la cantidad.',
                          ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed:
                                  busy || editingId != null || items.isEmpty
                                  ? null
                                  : () => _save(),
                              child: const Text('Guardar pedido'),
                            ),
                            FilledButton(
                              onPressed:
                                  busy ||
                                      editingId != null ||
                                      items.isEmpty ||
                                      o.lastEventId == null
                                  ? null
                                  : _review,
                              child: const Text('Revisar y confirmar'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
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
                      onPressed: busy || editingId != null || items.isEmpty
                          ? null
                          : _refreshBase,
                      child: const Text('Recuperar base y conservar captura'),
                    ),
                  Text(switch (o.status) {
                    'draft' =>
                      o.lastEventId == null ? 'Pedido sin guardar' : 'Borrador',
                    'confirmed' => 'Confirmado',
                    'partial' => 'Recibido parcialmente',
                    'received' => 'Recibido',
                    'cancelled' => 'Cancelado',
                    'closed' => 'Cerrado',
                    _ => 'Pedido',
                  }, style: Theme.of(context).textTheme.titleMedium),
                  ExpansionTile(
                    title: const Text('Información del pedido'),
                    children: [SelectableText('Pedido ${o.id}')],
                  ),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'El pedido está vacío. Agrega un producto para continuar.',
                      ),
                    ),
                  for (var i = 0; i < items.length; i++)
                    Card(
                      key: ValueKey(items[i].id),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                items[i].productNameSnapshot,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              trailing: !editable
                                  ? null
                                  : IconButton(
                                      tooltip: editingId == items[i].id
                                          ? 'Cerrar edición'
                                          : 'Editar artículo',
                                      onPressed:
                                          busy ||
                                              (editingId != null &&
                                                  editingId != items[i].id)
                                          ? null
                                          : () => setState(
                                              () => editingId =
                                                  editingId == items[i].id
                                                  ? null
                                                  : items[i].id,
                                            ),
                                      icon: Icon(
                                        editingId == items[i].id
                                            ? Icons.close
                                            : Icons.edit,
                                        size: 18,
                                      ),
                                    ),
                              subtitle: items[i].variantNameSnapshot == null
                                  ? null
                                  : Text(items[i].variantNameSnapshot!),
                              onTap:
                                  !editable ||
                                      busy ||
                                      (editingId != null &&
                                          editingId != items[i].id)
                                  ? null
                                  : () =>
                                        setState(() => editingId = items[i].id),
                            ),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                Text(
                                  '${_quantity(items[i], items[i].quantityAtomic)} × ${_price(items[i])}',
                                ),
                                Text(
                                  _money(items[i].totalMinor),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ],
                            ),
                            if (editable && editingId == items[i].id)
                              SupplierOrderQuantityEditor(
                                key: ValueKey('quantity-${items[i].id}'),
                                line: items[i],
                                onChanged: (line) => setState(() {
                                  items[i] = line;
                                  dirty = true;
                                }),
                                onClose: () => setState(() => editingId = null),
                                onDelete: () => _deleteLine(i),
                              ),
                            if (editable && editingId == null)
                              Wrap(
                                alignment: WrapAlignment.end,
                                children: [
                                  if (items[i].dimension == 'count') ...[
                                    IconButton(
                                      onPressed: busy
                                          ? null
                                          : () => _changeQuantity(i, -1),
                                      tooltip: 'Disminuir cantidad',
                                      icon: const Icon(Icons.remove),
                                    ),
                                    IconButton(
                                      onPressed:
                                          busy ||
                                              items[i].quantityAtomic >=
                                                  supplierOrderMaxInteger
                                          ? null
                                          : () => _changeQuantity(i, 1),
                                      tooltip: 'Aumentar cantidad',
                                      icon: const Icon(Icons.add),
                                    ),
                                  ],
                                  IconButton(
                                    onPressed: busy
                                        ? null
                                        : () => _deleteLine(i),
                                    tooltip: 'Eliminar artículo',
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _editPrice(i),
                                    child: const Text('Editar precio'),
                                  ),
                                ],
                              ),
                          ],
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
                      onPressed: busy || editingId != null || items.length >= 50
                          ? null
                          : _add,
                      child: const Text('Agregar variante'),
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
                  if (o.status == 'draft' && o.lastEventId != null)
                    TextButton(
                      onPressed: busy || editingId != null
                          ? null
                          : _deleteDraft,
                      child: const Text('Eliminar borrador'),
                    ),
                ],
              ),
      ),
    );
  }
}
