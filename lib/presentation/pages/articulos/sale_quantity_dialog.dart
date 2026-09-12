import 'package:flutter/material.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/inventario/unidad_inventario.dart';

class SaleQuantityDialog extends StatefulWidget {
  const SaleQuantityDialog({
    required this.productName,
    required this.unit,
    super.key,
  });
  final String productName;
  final UnidadInventario unit;
  @override
  State<SaleQuantityDialog> createState() => _SaleQuantityDialogState();
}

class _SaleQuantityDialogState extends State<SaleQuantityDialog> {
  final _controller = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      const InventoryQuantityCodec().parsePositiveAtomic(
        _controller.text,
        widget.unit,
      );
      Navigator.of(context).pop(_controller.text.trim());
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.productName),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: 'Cantidad (${widget.unit.simbolo})',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Agregar')),
    ],
  );
}
