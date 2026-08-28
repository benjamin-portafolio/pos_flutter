import 'package:flutter/material.dart';

import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../domain/inventario/recurso_inventario_listado.dart';
import 'models/inventory_adjustment_form_result.dart';
import 'widgets/inventory_quantity_input_formatter.dart';

class InventoryAdjustmentDialog extends StatefulWidget {
  const InventoryAdjustmentDialog({required this.resource, super.key});

  final RecursoInventarioListado resource;

  @override
  State<InventoryAdjustmentDialog> createState() =>
      _InventoryAdjustmentDialogState();
}

class _InventoryAdjustmentDialogState extends State<InventoryAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _adding = true;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.resource.unidadPredeterminada;
    return AlertDialog(
      title: Text('Actualizar ${widget.resource.nombre}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                key: const Key('inventory_adjustment_direction'),
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Agregar'),
                    icon: Icon(Icons.add),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Retirar'),
                    icon: Icon(Icons.remove),
                  ),
                ],
                selected: {_adding},
                onSelectionChanged: (selection) {
                  setState(() => _adding = selection.single);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('inventory_adjustment_quantity'),
                controller: _quantityController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  InventoryQuantityInputFormatter(unit.maximosDecimales),
                ],
                decoration: InputDecoration(
                  labelText: 'Cantidad *',
                  suffixText: unit.simbolo,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  try {
                    const InventoryQuantityCodec().parsePositiveAtomic(
                      value ?? '',
                      unit,
                    );
                    return null;
                  } on FormatException catch (error) {
                    return error.message;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('inventory_adjustment_reason'),
                controller: _reasonController,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final normalized = value?.trim() ?? '';
                  return normalized.isEmpty ? 'Ingresa el motivo.' : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          key: const Key('save_inventory_adjustment'),
          onPressed: _save,
          child: const Text('GUARDAR'),
        ),
      ],
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final atomic = const InventoryQuantityCodec().parsePositiveAtomic(
      _quantityController.text,
      widget.resource.unidadPredeterminada,
    );
    Navigator.of(context).pop(
      InventoryAdjustmentFormResult(
        quantityDeltaAtomic: _adding ? atomic : -atomic,
        reason: _reasonController.text.trim(),
      ),
    );
  }
}
