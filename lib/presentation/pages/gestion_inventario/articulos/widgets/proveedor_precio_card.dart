import 'package:flutter/material.dart';

import '../models/proveedor_precio_form.dart';

/// Selección explícita y campos de una pareja proveedor/variante.
class ProveedorPrecioCard extends StatelessWidget {
  const ProveedorPrecioCard({
    required this.id,
    required this.nombre,
    required this.form,
    required this.controller,
    required this.onSelected,
    required this.onPriceChanged,
    required this.onDate,
    this.priceError,
    this.dateError,
    super.key,
  });

  final String id;
  final String nombre;
  final ProveedorPrecioForm? form;
  final TextEditingController controller;
  final ValueChanged<bool> onSelected;
  final ValueChanged<String> onPriceChanged;
  final VoidCallback onDate;
  final String? priceError;
  final String? dateError;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            key: Key('select_variant_supplier_$id'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(nombre),
            value: form != null,
            onChanged: (value) => onSelected(value ?? false),
          ),
          if (form != null) ...[
            const SizedBox(height: 8),
            TextField(
              key: Key('supplier_price_$id'),
              controller: controller,
              onChanged: onPriceChanged,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Precio informado *',
                prefixText: '\$ ',
                hintText: '0.00',
                errorText: priceError,
                errorMaxLines: 4,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: Key('supplier_date_$id'),
              onPressed: form!.conservaFecha ? null : onDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                'Fecha informada: ${_dateText()}',
                textAlign: TextAlign.center,
              ),
            ),
            if (dateError != null)
              Text(
                dateError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              form!.conservaFecha
                  ? 'La fecha se conserva mientras el precio no cambie.'
                  : 'Selecciona la fecha local del precio informado.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );

  String _dateText() {
    if (form!.conservaFecha) {
      return ProveedorPrecioForm.formatDate(form!.original!.fechaInformadaMs);
    }
    final date = form!.fecha;
    return date == null
        ? 'Seleccionar'
        : ProveedorPrecioForm.formatDate(date.toUtc().millisecondsSinceEpoch);
  }
}
