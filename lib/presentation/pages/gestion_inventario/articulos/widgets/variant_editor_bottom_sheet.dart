import 'package:flutter/material.dart';

import '../../../../../domain/articulos/costo_estandar.dart';
import '../../../../../domain/articulos/nombre_variante.dart';
import '../../../../../domain/articulos/precio_venta.dart';
import '../models/articulo_form_result.dart';
import 'currency_input_formatter.dart';

class VariantEditorBottomSheet extends StatefulWidget {
  const VariantEditorBottomSheet({
    required this.initialValue,
    required this.canDelete,
    required this.existingNameKeys,
    super.key,
  });

  final ArticuloFormVarianteResult? initialValue;
  final bool canDelete;
  final Set<String> existingNameKeys;

  @override
  State<VariantEditorBottomSheet> createState() =>
      _VariantEditorBottomSheetState();
}

class _VariantEditorBottomSheetState
    extends State<VariantEditorBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _nameController = TextEditingController(text: initial?.nombre ?? '');
    _priceController = TextEditingController(
      text: initial?.precioVenta ?? '',
    );
    _costController = TextEditingController(
      text: initial?.costoEstandar ?? '',
    );
    _priceController.addListener(_refreshCalculatedValues);
    _costController.addListener(_refreshCalculatedValues);
  }

  @override
  void dispose() {
    _priceController.removeListener(_refreshCalculatedValues);
    _costController.removeListener(_refreshCalculatedValues);
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.initialValue == null
                            ? 'Agregar variante'
                            : 'Editar variante',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      key: const Key('close_variant_editor_button'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('variant_name_field'),
                  controller: _nameController,
                  maxLength: 160,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la variante (opcional)',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateName,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('variant_sale_price_field'),
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [CurrencyInputFormatter()],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Precio de venta *',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePrice,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('variant_standard_cost_field'),
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: const [CurrencyInputFormatter()],
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Costo estándar (opcional)',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateCost,
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                _ReadOnlyValue(
                  label: 'Margen estimado (%)',
                  value: _estimatedMargin,
                  valueKey: const Key('variant_margin_value'),
                ),
                const SizedBox(height: 8),
                const _ReadOnlyValue(
                  label: 'Existencias disponibles',
                  value: '—',
                  valueKey: Key('variant_available_stock_value'),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  key: const Key('delete_variant_button'),
                  onPressed: widget.canDelete
                      ? () => Navigator.of(
                          context,
                        ).pop(const VariantEditorResult.deleted())
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar variante'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('save_variant_button'),
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Guardar variante'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _validateName(String? value) {
    try {
      final name = NombreVariante.fromInput(value);
      final nameKey = name.nameKey;
      if (nameKey != null && widget.existingNameKeys.contains(nameKey)) {
        return 'Ya existe una variante con este nombre.';
      }
      return null;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? 'Nombre inválido.';
    }
  }

  String? _validatePrice(String? value) {
    try {
      PrecioVenta.fromInput(value ?? '');
      return null;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? 'Precio inválido.';
    }
  }

  String? _validateCost(String? value) {
    try {
      CostoEstandar.fromInput(value);
      return null;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? 'Costo inválido.';
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = NombreVariante.fromInput(_nameController.text);
    Navigator.of(context).pop(
      VariantEditorResult.saved(
        ArticuloFormVarianteResult(
          nombre: name.value,
          precioVenta: _priceController.text.trim().replaceAll(',', '.'),
          costoEstandar: CostoEstandar.fromInput(_costController.text) == null
              ? null
              : _costController.text.trim().replaceAll(',', '.'),
        ),
      ),
    );
  }

  void _refreshCalculatedValues() => setState(() {});

  String get _estimatedMargin {
    try {
      final sale = PrecioVenta.fromInput(_priceController.text).unidadMenor;
      final cost = CostoEstandar.fromInput(_costController.text)?.unidadMenor;
      if (cost == null) return '—';

      final numerator = BigInt.from(sale - cost) * BigInt.from(10000);
      final denominator = BigInt.from(sale);
      final negative = numerator.isNegative;
      final absolute = numerator.abs();
      final rounded =
          (absolute + denominator ~/ BigInt.from(2)) ~/ denominator;
      final hundredths = negative ? -rounded : rounded;
      final sign = hundredths.isNegative ? '-' : '';
      final digits = hundredths.abs().toString().padLeft(3, '0');
      final whole = digits.substring(0, digits.length - 2);
      final decimals = digits.substring(digits.length - 2);
      final trimmedDecimals = decimals.replaceFirst(RegExp(r'0+$'), '');
      return trimmedDecimals.isEmpty
          ? '$sign$whole %'
          : '$sign$whole.$trimmedDecimals %';
    } on ArgumentError {
      return '—';
    }
  }
}

class VariantEditorResult {
  const VariantEditorResult.saved(this.value) : deleted = false;

  const VariantEditorResult.deleted() : value = null, deleted = true;

  final ArticuloFormVarianteResult? value;
  final bool deleted;
}

class _ReadOnlyValue extends StatelessWidget {
  const _ReadOnlyValue({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value, key: valueKey),
    );
  }
}
