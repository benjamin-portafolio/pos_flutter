import '../../../../application/sync/payloads/supplier_receipt_confirmed_payload.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/di/injection.dart';
import '../../../../application/proveedores/supplier_order_detail.dart';
import '../../../../application/proveedores/supplier_order_reader.dart';
import '../../../../application/commands/proveedores/supplier_order_command_service.dart';
import '../../../../application/commands/proveedores/confirm_supplier_receipt_command.dart';
import '../../../../application/commands/proveedores/supplier_receipt_input_line.dart';
import '../../../../application/sync/projections/supplier_order_projection_store.dart';
import '../../../../application/sync/payloads/supplier_order_line.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import 'supplier_order_forms.dart';

/// Unconfirmed capture lives only in this route; leaving explicitly discards it.
class SupplierReceiptScreen extends StatefulWidget {
  const SupplierReceiptScreen({
    required this.initial,
    this.conforming = false,
    this.source,
    super.key,
  });
  final SupplierOrderDetail initial;
  final bool conforming;
  final SupplierReceiptConfirmedPayload? source;
  @override
  State<SupplierReceiptScreen> createState() => _SupplierReceiptScreenState();
}

class _SupplierReceiptScreenState extends State<SupplierReceiptScreen> {
  late SupplierOrderDetail basis = widget.initial;
  late final quantities = {
    for (final l in basis.order.document.items)
      l.id: TextEditingController(text: _q(l, basis.pending(l))),
  };
  late final prices = {
    for (final l in basis.order.document.items)
      l.id: TextEditingController(
        text: l.quotedPriceMinor == null ? '' : orderMoney(l.quotedPriceMinor),
      ),
  };
  final errors = <String, String>{};
  final acknowledgments = <String>{};
  ConfirmSupplierReceiptCommand? attempt;
  bool reviewing = false, busy = false, completed = false;
  String? message;
  String _q(SupplierOrderLine l, int n) =>
      const InventoryQuantityCodec().formatAtomic(n, lineUnit(l));
  @override
  void initState() {
    super.initState();
    final source = widget.source;
    if (source != null) {
      for (final l in basis.order.document.items) {
        final matches = source.items.where((i) => i.orderItemId == l.id);
        quantities[l.id]!.text = _q(
          l,
          matches.isEmpty ? 0 : matches.single.quantityAtomic,
        );
        if (matches.isNotEmpty) {
          prices[l.id]!.text = orderMoney(matches.single.actualPriceMinor);
        }
      }
      message =
          'Intención del intento rechazado ${source.receiptId}. No se reenvía: revisa la base para confirmar una nueva recepción con identidad propia.';
    }
    if (widget.conforming) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _review());
    }
  }

  @override
  void dispose() {
    for (final c in [...quantities.values, ...prices.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<SupplierReceiptInputLine> _inputs() {
    errors.clear();
    final rows = <SupplierReceiptInputLine>[];
    for (final l in basis.order.document.items) {
      try {
        final q = const InventoryQuantityCodec().parseNonNegativeAtomic(
          quantities[l.id]!.text,
          lineUnit(l),
        );
        // A missing price on an unreceived line is irrelevant, never a free entry.
        final text = prices[l.id]!.text.trim().replaceAll(',', '.');
        if (q > 0 && !RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text)) {
          throw const FormatException(
            'Ingresa el precio real; cero es válido.',
          );
        }
        final parts = text.split('.');
        final price = q == 0
            ? BigInt.zero
            : BigInt.parse(parts[0]) * BigInt.from(100) +
                  BigInt.parse(
                    parts.length == 1 ? '0' : parts[1].padRight(2, '0'),
                  );
        if (price > BigInt.from(9007199254740991)) {
          throw const FormatException('Precio fuera de rango.');
        }
        final input = SupplierReceiptInputLine(
          orderItemId: l.id,
          movementId: const Uuid().v4(),
          quantityAtomic: q,
          actualPriceMinor: price.toInt(),
          referenceQuantityAtomic: l.referenceQuantityAtomic,
          overageAcknowledged: acknowledgments.contains(l.id),
        );
        input.validatedJson();
        rows.add(input);
      } catch (e) {
        errors[l.id] = '$e';
      }
    }
    return rows;
  }

  Future<void> _review() async {
    if (busy || completed) return;
    setState(() => busy = true);
    try {
      if (attempt != null) {
        final saved = await getIt<SupplierOrderProjectionStore>().eventById(
          attempt!.eventId,
        );
        if (saved != null) {
          if (mounted) {
            setState(() {
              completed = true;
              reviewing = false;
              message =
                  'Intento conservado: ${deliveryLabel(saved.deliveryStatus)}. ${saved.rejectionReason ?? ''} Consulta el detalle; no se ejecutará otra vez.';
            });
          }
          return;
        }
      }
      final current = await getIt<SupplierOrderReader>().readDetail(
        basis.order.id,
      );
      if (current == null) {
        throw StateError(
          'El pedido ya no está disponible. La captura se conserva.',
        );
      }
      final changed = current.reviewBasis != basis.reviewBasis;
      basis = current;
      attempt = null;
      acknowledgments.clear();
      final inputs = _inputs();
      if (errors.isNotEmpty) {
        reviewing = false;
        message = 'Corrige las partidas indicadas.';
      } else if (!inputs.any((i) => i.quantityAtomic > 0)) {
        reviewing = false;
        message = 'No hay mercancía recibida. Cero no genera movimientos.';
      } else {
        reviewing = true;
        message = changed
            ? 'Cambió la base. Conservamos cantidades y precios; revisa nuevamente saldos, pendientes y excesos.'
            : null;
      }
    } catch (e) {
      message = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirm() async {
    if (busy || completed) return;
    setState(() => busy = true);
    try {
      // A retained attempt always reuses its original IDs and content.
      if (attempt == null) {
        final current = await getIt<SupplierOrderReader>().readDetail(
          basis.order.id,
        );
        if (current == null || current.reviewBasis != basis.reviewBasis) {
          reviewing = false;
          acknowledgments.clear();
          throw StateError(
            'Cambió la base. La captura se conserva; vuelve a revisar.',
          );
        }
        final inputs = _inputs();
        if (errors.isNotEmpty) throw StateError('Corrige las partidas.');
        for (final i in inputs) {
          final l = basis.order.document.items.singleWhere(
            (l) => l.id == i.orderItemId,
          );
          if (i.quantityAtomic > basis.pending(l) && !i.overageAcknowledged) {
            throw StateError('Revisa y acepta explícitamente cada exceso.');
          }
        }
        attempt = ConfirmSupplierReceiptCommand.capture(
          eventId: const Uuid().v4(),
          orderId: basis.order.id,
          baseEventId: basis.order.lastEventId!,
          receiptId: const Uuid().v4(),
          occurredAtMs: DateTime.now().millisecondsSinceEpoch,
          items: inputs,
          catalogBasis: Map.unmodifiable(basis.catalogBasis),
        );
      }
      await getIt<SupplierOrderCommandService>().receive(attempt!);
      if (!mounted) return;
      setState(() {
        completed = true;
        reviewing = false;
        message =
            'Recepción guardada localmente. Consulta su estado en el detalle. Identificador: ${attempt!.payload.receiptId}';
      });
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _leave() async {
    if (busy) return;
    if (!completed) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Descartar captura sin confirmar'),
          content: const Text(
            'Esta captura no es una recepción guardada. Al salir se descarta; cerrar la aplicación tampoco recupera este formulario.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Descartar y salir'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final inputs = reviewing ? _inputs() : <SupplierReceiptInputLine>[];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 80,
          title: Text(
            reviewing ? 'Revisar recepción' : 'Recibir mercancía',
            maxLines: 2,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: busy ? null : _leave,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(basis.order.document.supplierNameSnapshot),
            const Text(
              'La confirmación suma entradas al saldo vigente. El pedido original conserva cantidades y precios.',
            ),
            if (message != null)
              Text(message!, key: const ValueKey('receipt-message')),
            if (!completed) ...[
              for (final l in basis.order.document.items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l.productNameSnapshot} ${l.variantNameSnapshot ?? ''}',
                        ),
                        Text(
                          'Pedido: ${_q(l, l.quantityAtomic)} · Recibido anteriormente: ${_q(l, basis.received[l.id] ?? 0)} · Pendiente: ${_q(l, basis.pending(l))} ${l.unitSymbolSnapshot}',
                        ),
                        if (!reviewing) ...[
                          TextField(
                            key: ValueKey('quantity-${l.id}'),
                            controller: quantities[l.id],
                            enabled: !busy && attempt == null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Cantidad recibida (${l.unitSymbolSnapshot})',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          TextField(
                            key: ValueKey('price-${l.id}'),
                            controller: prices[l.id],
                            enabled: !busy && attempt == null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Precio real por ${_q(l, l.referenceQuantityAtomic)} ${l.unitSymbolSnapshot}',
                              helperMaxLines: 3,
                              helperText:
                                  'Moneda: ${basis.order.document.currency}; cero recibido no genera entrada.',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ] else if (inputs.any(
                          (i) => i.orderItemId == l.id,
                        )) ...[
                          for (final i in inputs.where(
                            (i) => i.orderItemId == l.id,
                          )) ...[
                            Text(
                              'Esta recepción: ${_q(l, i.quantityAtomic)} ${l.unitSymbolSnapshot}\nSaldo vigente ${_q(l, basis.balances[l.inventoryItemId] ?? 0)} + entrada ${_q(l, i.quantityAtomic)} = saldo previsto ${_q(l, (basis.balances[l.inventoryItemId] ?? 0) + i.quantityAtomic)} ${l.unitSymbolSnapshot}\nPrecio real: ${orderMoney(i.actualPriceMinor)} por ${_q(l, l.referenceQuantityAtomic)} ${l.unitSymbolSnapshot}\nImporte real: ${orderMoney(i.validatedJson()['total_minor'] as int)} ${basis.order.document.currency}',
                            ),
                            if (i.quantityAtomic > basis.pending(l))
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Acepto el exceso de ${_q(l, i.quantityAtomic - basis.pending(l))} ${l.unitSymbolSnapshot}',
                                ),
                                value: acknowledgments.contains(l.id),
                                onChanged: busy
                                    ? null
                                    : (v) => setState(() {
                                        if (v == true) {
                                          acknowledgments.add(l.id);
                                        } else {
                                          acknowledgments.remove(l.id);
                                        }
                                      }),
                              ),
                          ],
                        ],
                        if (errors[l.id] != null)
                          Text(
                            errors[l.id]!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (reviewing)
                Text(
                  'Importe real de esta recepción: ${orderMoney(inputs.fold<int>(0, (v, i) => v + (i.validatedJson()['total_minor'] as int)))} ${basis.order.document.currency}',
                ),
              if (reviewing)
                TextButton(
                  onPressed: busy || attempt != null
                      ? null
                      : () => setState(() => reviewing = false),
                  child: const Text('Volver a editar'),
                ),
              FilledButton(
                onPressed: busy
                    ? null
                    : reviewing
                    ? _confirm
                    : _review,
                child: Text(
                  reviewing
                      ? (attempt == null
                            ? 'Confirmar entrada de inventario'
                            : 'Reintentar el mismo intento')
                      : 'Revisar recepción',
                ),
              ),
              if (attempt != null)
                TextButton(
                  onPressed: busy ? null : _review,
                  child: const Text('Consultar resultado y revisar'),
                ),
            ],
            TextButton(
              onPressed: busy ? null : _leave,
              child: Text(completed ? 'Volver al detalle' : 'Cancelar edición'),
            ),
          ],
        ),
      ),
    );
  }
}

String deliveryLabel(String value) => switch (value) {
  'not_required' => 'Guardado local · sin sincronización requerida',
  'pending' => 'Guardado local · sincronización pendiente',
  'delivered' => 'Aceptación remota',
  'conflict' => 'Conflicto · operación no aceptada',
  'rejected' => 'Rechazada · operación no aceptada',
  _ => value,
};
