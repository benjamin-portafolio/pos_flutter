import '../../../../domain/inventario/unidad_inventario.dart';
import 'package:flutter/material.dart';
import '../../../../application/edicion_masiva/fila_catalogo_masivo.dart';
import '../../../../application/sync/payloads/supplier_replenishment_patch.dart';
import '../../../../domain/inventario/inventory_quantity_codec.dart';

Future<SupplierReplenishmentPatch?> capturarReposicionMasiva(
  BuildContext context,
  FilaCatalogoMasivo row,
  SupplierReplenishmentPatch initial,
) => showDialog<SupplierReplenishmentPatch>(
  context: context,
  builder: (_) => _ReplenishmentDialog(row: row, initial: initial),
);

class _ReplenishmentDialog extends StatefulWidget {
  const _ReplenishmentDialog({required this.row, required this.initial});
  final FilaCatalogoMasivo row;
  final SupplierReplenishmentPatch initial;
  @override
  State<_ReplenishmentDialog> createState() => _ReplenishmentDialogState();
}

class _ReplenishmentDialogState extends State<_ReplenishmentDialog> {
  static const codec = InventoryQuantityCodec();
  late String supplierAction, targetAction;
  String? supplier;
  late final TextEditingController text;
  final form = GlobalKey<FormState>();
  FilaCatalogoMasivo get row => widget.row;
  UnidadInventario? get unit => row.entrada?.unidad;
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    supplierAction = initial.hasSupplier
        ? initial.supplierId == null
              ? 'retirar'
              : 'establecer'
        : 'conservar';
    targetAction = initial.hasTarget
        ? initial.targetAtomic == null
              ? 'retirar'
              : 'establecer'
        : 'conservar';
    supplier = initial.hasSupplier ? initial.supplierId : row.currentSupplierId;
    final target = initial.hasTarget
        ? initial.targetAtomic
        : row.targetStockAtomic;
    text = TextEditingController(
      text: target == null || unit == null
          ? ''
          : codec.formatAtomic(target, unit!),
    );
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Configurar reposición'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: const Key('replenishment_supplier_action'),
              initialValue: supplierAction,
              decoration: const InputDecoration(
                labelText: 'Proveedor actual: acción',
              ),
              items: [
                for (final a in ['conservar', 'establecer', 'retirar'])
                  DropdownMenuItem(value: a, child: Text(a)),
              ],
              onChanged: (v) => setState(() => supplierAction = v!),
            ),
            if (supplierAction == 'establecer')
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: supplier,
                decoration: const InputDecoration(
                  labelText: 'Proveedor asociado (UUID)',
                ),
                items: [
                  for (final p in row.proveedores)
                    DropdownMenuItem(
                      value: p.proveedorId,
                      child: Text(p.proveedorId),
                    ),
                ],
                onChanged: (v) => supplier = v,
                validator: (v) =>
                    v == null ? 'Selecciona una relación existente.' : null,
              ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: const Key('replenishment_target_action'),
              initialValue: targetAction,
              decoration: const InputDecoration(labelText: 'Objetivo: acción'),
              items: [
                for (final a in ['conservar', 'establecer', 'retirar'])
                  DropdownMenuItem(value: a, child: Text(a)),
              ],
              onChanged: (v) => setState(() => targetAction = v!),
            ),
            if (targetAction == 'establecer')
              TextFormField(
                key: const Key('replenishment_target_input'),
                controller: text,
                decoration: InputDecoration(
                  labelText: 'Existencia objetivo',
                  suffixText: unit?.simbolo,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  try {
                    if (unit == null) {
                      return 'Falta seguimiento directo con unidad válida.';
                    }
                    codec.parseNonNegativeAtomic(value ?? '', unit!);
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(
            context,
            SupplierReplenishmentPatch.fromJson({
              if (supplierAction != 'conservar')
                'current_supplier_id': supplierAction == 'retirar'
                    ? null
                    : supplier,
              if (targetAction != 'conservar')
                'target_stock_atomic': targetAction == 'retirar'
                    ? null
                    : codec.parseNonNegativeAtomic(text.text, unit!),
            }),
          );
        },
        child: const Text('Revisar'),
      ),
    ],
  );
}
