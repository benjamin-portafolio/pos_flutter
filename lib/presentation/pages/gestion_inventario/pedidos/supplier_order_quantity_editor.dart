import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../application/sync/payloads/supplier_order_line.dart';
import '../../../../application/sync/payloads/supplier_order_json.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../recursos/widgets/inventory_quantity_input_formatter.dart';
import 'supplier_order_forms.dart';

class SupplierOrderQuantityEditor extends StatefulWidget {
  const SupplierOrderQuantityEditor({
    required this.line,
    required this.onChanged,
    required this.onClose,
    required this.onDelete,
    super.key,
  });
  final SupplierOrderLine line;
  final ValueChanged<SupplierOrderLine> onChanged;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  @override
  State<SupplierOrderQuantityEditor> createState() =>
      _SupplierOrderQuantityEditorState();
}

class _SupplierOrderQuantityEditorState
    extends State<SupplierOrderQuantityEditor> {
  late final controller = TextEditingController.fromValue(
    TextEditingValue(
      text: quantityText,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: quantityText.length,
      ),
    ),
  );
  String get quantityText => const InventoryQuantityCodec().formatAtomic(
    widget.line.quantityAtomic,
    lineUnit(widget.line),
  );
  String? error;
  int? get parsed {
    try {
      return const InventoryQuantityCodec().parsePositiveAtomic(
        controller.text,
        lineUnit(widget.line),
      );
    } on FormatException {
      return null;
    }
  }

  int get step => widget.line.dimension == 'count'
      ? 1
      : widget.line.referenceQuantityAtomic;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void apply({bool close = false}) {
    try {
      final quantity = const InventoryQuantityCodec().parsePositiveAtomic(
        controller.text,
        lineUnit(widget.line),
      );
      final price = widget.line.quotedPriceMinor;
      final line = SupplierOrderLine.fromJson({
        ...widget.line.toJson(),
        'quantity_atomic': quantity,
        'total_minor': price == null
            ? null
            : orderAmount(price, quantity, widget.line.referenceQuantityAtomic),
      });
      widget.onChanged(line);
      setState(() => error = null);
      if (close) widget.onClose();
    } on FormatException catch (e) {
      setState(() => error = e.message.toString());
    }
  }

  void change(int delta) {
    final value = parsed;
    if (value == null) return;
    final next = value + delta;
    if (next < 0 || next > supplierOrderMaxInteger) return;
    if (next == 0) {
      widget.onDelete();
      return;
    }
    controller.text = const InventoryQuantityCodec().formatAtomic(
      next,
      lineUnit(widget.line),
    );
    apply();
  }

  @override
  Widget build(BuildContext context) {
    final value = parsed;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Disminuir cantidad',
                onPressed: value != null && value >= step
                    ? () => change(-step)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: TextField(
                  key: const Key('order_quantity_field'),
                  controller: controller,
                  autofocus: true,
                  selectAllOnFocus: false,
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: widget.line.dimension != 'count',
                  ),
                  inputFormatters: [
                    InventoryQuantityInputFormatter(
                      lineUnit(widget.line).maximosDecimales,
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Cantidad',
                    suffixText: widget.line.dimension == 'count'
                        ? null
                        : widget.line.unitSymbolSnapshot,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    setState(() {
                      try {
                        const InventoryQuantityCodec().parsePositiveAtomic(
                          controller.text,
                          lineUnit(widget.line),
                        );
                        error = null;
                      } on FormatException catch (e) {
                        error = e.message.toString();
                      }
                    });
                  },
                  onEditingComplete: () {},
                  onSubmitted: (_) => apply(close: true),
                ),
              ),
              IconButton(
                tooltip: 'Aumentar cantidad',
                onPressed:
                    value != null && value <= supplierOrderMaxInteger - step
                    ? () => change(step)
                    : null,
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: 'Eliminar artículo',
                color: Theme.of(context).colorScheme.error,
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onClose,
                child: const Text('Cancelar edición'),
              ),
              FilledButton(
                onPressed: value == null ? null : () => apply(close: true),
                child: const Text('Listo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
