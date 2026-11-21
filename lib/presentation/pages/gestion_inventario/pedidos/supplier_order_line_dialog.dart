import 'package:flutter/material.dart';
import '../../../../application/sync/payloads/supplier_order_line.dart';
import '../../../../application/sync/payloads/supplier_order_json.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import 'supplier_order_forms.dart';

class SupplierOrderLineDialog extends StatefulWidget {
  const SupplierOrderLineDialog({required this.line, super.key});
  final SupplierOrderLine line;
  @override
  State<SupplierOrderLineDialog> createState() =>
      _SupplierOrderLineDialogState();
}

class _SupplierOrderLineDialogState extends State<SupplierOrderLineDialog> {
  late final quantity = TextEditingController(
    text: const InventoryQuantityCodec().formatAtomic(
      widget.line.quantityAtomic,
      lineUnit(widget.line),
    ),
  );
  late final price = TextEditingController(
    text: widget.line.quotedPriceMinor == null
        ? ''
        : orderMoney(widget.line.quotedPriceMinor),
  );
  String? error;
  @override
  void dispose() {
    quantity.dispose();
    price.dispose();
    super.dispose();
  }

  void save() {
    try {
      final q = const InventoryQuantityCodec().parsePositiveAtomic(
        quantity.text,
        lineUnit(widget.line),
      );
      final text = price.text.trim().replaceAll(',', '.');
      int? p;
      if (text.isNotEmpty) {
        if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text)) {
          throw const FormatException('Precio inválido.');
        }
        final parts = text.split('.');
        final value =
            BigInt.parse(parts[0]) * BigInt.from(100) +
            BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
        if (value > BigInt.from(9007199254740991)) {
          throw const FormatException('Precio fuera de rango.');
        }
        p = value.toInt();
      }
      final line = SupplierOrderLine.fromJson({
        ...widget.line.toJson(),
        'quantity_atomic': q,
        'quoted_price_minor': p,
        'total_minor': p == null
            ? null
            : orderAmount(p, q, widget.line.referenceQuantityAtomic),
      });
      Navigator.pop(context, line);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.line.productNameSnapshot),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: quantity,
            decoration: InputDecoration(
              labelText: 'Cantidad (${widget.line.unitSymbolSnapshot})',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          TextField(
            controller: price,
            decoration: InputDecoration(
              labelText:
                  'Precio por ${const InventoryQuantityCodec().formatAtomic(widget.line.referenceQuantityAtomic, lineUnit(widget.line))} ${widget.line.unitSymbolSnapshot}',
              helperText: 'Vacío: desconocido; cero: precio explícito',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Volver'),
      ),
      FilledButton(onPressed: save, child: const Text('Aplicar')),
    ],
  );
}
