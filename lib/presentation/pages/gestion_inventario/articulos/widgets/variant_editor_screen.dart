import 'package:flutter/material.dart';

import '../../../../../domain/articulos/costo_estandar.dart';
import '../../../../../domain/articulos/nombre_variante.dart';
import '../../../../../domain/articulos/precio_venta.dart';
import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../../domain/inventario/unidad_inventario.dart';
import '../../../../../domain/repositories/recurso_inventario_repository.dart';
import '../../recursos/models/inventory_resource_form_result.dart';
import '../../recursos/widgets/inventory_quantity_input_formatter.dart';
import '../models/articulo_form_result.dart';
import '../models/recipe_component_form_result.dart';
import 'currency_input_formatter.dart';
import 'recipe_editor_screen.dart';

class VariantEditorScreen extends StatefulWidget {
  const VariantEditorScreen({
    required this.initialValue,
    required this.canDelete,
    required this.existingNameKeys,
    required this.inventoryUnit,
    this.inventoryUnits = const [],
    this.inventoryResourceRepository,
    this.onCreateInventoryResource,
    super.key,
  });

  final ArticuloFormVarianteResult? initialValue;
  final bool canDelete;
  final Set<String> existingNameKeys;
  final UnidadInventario inventoryUnit;
  final List<UnidadInventario> inventoryUnits;
  final RecursoInventarioRepository? inventoryResourceRepository;
  final Future<void> Function(InventoryResourceFormResult result)?
  onCreateInventoryResource;

  @override
  State<VariantEditorScreen> createState() => _VariantEditorScreenState();
}

class _VariantEditorScreenState extends State<VariantEditorScreen> {
  static const _saveColor = Color(0xFF4CAF50);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;
  late final TextEditingController _initialStockController;
  late bool _trackingInventory;
  late bool _recipeEnabled;
  late List<RecipeComponentFormResult> _recipeComponents;
  String? _recipeError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _nameController = TextEditingController(text: initial?.nombre ?? '');
    _priceController = TextEditingController(text: initial?.precioVenta ?? '');
    _costController = TextEditingController(text: initial?.costoEstandar ?? '');
    _initialStockController = TextEditingController(
      text: initial?.existenciaInicial ?? '',
    );
    _trackingInventory = initial?.seguimientoExistencias ?? false;
    _recipeComponents = List.of(initial?.recipeComponents ?? const []);
    _recipeEnabled = _recipeComponents.isNotEmpty;
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
    _initialStockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('variant_editor_screen'),
      backgroundColor: const Color(0xFFE6E6E6),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('close_variant_editor_button'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Cerrar',
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const Key('delete_variant_button'),
                onPressed: widget.canDelete
                    ? () => Navigator.of(
                        context,
                      ).pop(const VariantEditorResult.deleted())
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  disabledBackgroundColor: colorScheme.error.withValues(
                    alpha: 0.35,
                  ),
                  disabledForegroundColor: colorScheme.onError.withValues(
                    alpha: 0.85,
                  ),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('ELIMINAR'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('save_variant_button'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _saveColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(
                  widget.initialValue == null ? 'AGREGAR' : 'GUARDAR',
                ),
              ),
            ),
          ],
        ),
        actions: const [SizedBox(width: 8)],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EditorCard(
                  child: TextFormField(
                    key: const Key('variant_name_field'),
                    controller: _nameController,
                    maxLength: 160,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la variante (opcional)',
                      hintText: 'Ej. 500 g, azul, grande',
                      counterText: '',
                      border: InputBorder.none,
                    ),
                    validator: _validateName,
                  ),
                ),
                const SizedBox(height: 12),
                _EditorCard(
                  child: Row(
                    key: const Key('variant_pricing_row'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _CompactMoneyField(
                          columnKey: const Key('variant_sale_price_column'),
                          fieldKey: const Key('variant_sale_price_field'),
                          label: 'Precio de venta *',
                          controller: _priceController,
                          textInputAction: TextInputAction.next,
                          validator: _validatePrice,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactMoneyField(
                          columnKey: const Key('variant_standard_cost_column'),
                          fieldKey: const Key('variant_standard_cost_field'),
                          label: 'Costo estándar',
                          controller: _costController,
                          signed: true,
                          textInputAction: TextInputAction.done,
                          validator: _validateCost,
                          onFieldSubmitted: (_) => _save(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactReadOnlyValue(
                          key: const Key('variant_margin_column'),
                          label: 'Margen estimado',
                          value: _estimatedMargin,
                          valueKey: const Key('variant_margin_value'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _EditorCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        key: const Key('variant_inventory_tracking_switch'),
                        contentPadding: EdgeInsets.zero,
                        value: _trackingInventory,
                        onChanged: (value) => setState(() {
                          _trackingInventory = value;
                          if (!value) _initialStockController.clear();
                          if (value) {
                            _recipeEnabled = false;
                            _recipeError = null;
                          }
                        }),
                        title: const Text('Seguimiento de existencias'),
                        subtitle: Text(
                          'Cada variante usa un recurso directo en ${widget.inventoryUnit.simbolo}.',
                        ),
                        secondary: const Icon(Icons.inventory_2_outlined),
                      ),
                      if (_trackingInventory) ...[
                        const Divider(),
                        TextFormField(
                          key: const Key('variant_initial_stock_field'),
                          controller: _initialStockController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            InventoryQuantityInputFormatter(
                              widget.inventoryUnit.maximosDecimales,
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Existencia inicial (opcional)',
                            suffixText: widget.inventoryUnit.simbolo,
                            helperText:
                                'Se registrará como movimiento inicial; el saldo comienza en cero si queda vacío.',
                            border: InputBorder.none,
                          ),
                          validator: _validateInitialStock,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _EditorCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        key: const Key('variant_recipe_checkbox'),
                        contentPadding: EdgeInsets.zero,
                        value: _recipeEnabled,
                        onChanged:
                            widget.inventoryResourceRepository == null ||
                                widget.onCreateInventoryResource == null
                            ? null
                            : (value) => setState(() {
                                _recipeEnabled = value ?? false;
                                _recipeError = null;
                                if (_recipeEnabled) {
                                  _trackingInventory = false;
                                  _initialStockController.clear();
                                }
                              }),
                        title: const Text('Receta'),
                        subtitle: const Text(
                          'Define los recursos de inventario consumidos por esta variante.',
                        ),
                        secondary: const Icon(Icons.restaurant_menu_outlined),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: const Key('manage_variant_recipe_button'),
                        onPressed: _recipeEnabled ? _openRecipeEditor : null,
                        icon: const Icon(Icons.tune),
                        label: const Text('ADMINISTRAR LA RECETA'),
                      ),
                      if (_recipeError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _recipeError!,
                          key: const Key('variant_recipe_error'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.error),
                        ),
                      ],
                      if (_recipeEnabled && _recipeComponents.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final component in _recipeComponents)
                              Chip(
                                key: Key(
                                  'variant_recipe_component_${component.resource.id}',
                                ),
                                label: Text(
                                  '${component.quantity} '
                                  '${component.resource.unidadPredeterminada.simbolo} '
                                  '${component.resource.nombre}',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
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

  String? _validateInitialStock(String? value) {
    if (!_trackingInventory || value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      const InventoryQuantityCodec().parseNonNegativeAtomic(
        value,
        widget.inventoryUnit,
      );
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_recipeEnabled && _recipeComponents.isEmpty) {
      setState(() {
        _recipeError = 'Agrega al menos un componente con cantidad positiva.';
      });
      return;
    }
    final name = NombreVariante.fromInput(_nameController.text);
    Navigator.of(context).pop(
      VariantEditorResult.saved(
        ArticuloFormVarianteResult(
          nombre: name.value,
          precioVenta: _priceController.text.trim().replaceAll(',', '.'),
          costoEstandar: CostoEstandar.fromInput(_costController.text) == null
              ? null
              : _costController.text.trim().replaceAll(',', '.'),
          inventoryUnitId: _trackingInventory ? widget.inventoryUnit.id : null,
          existenciaInicial:
              _trackingInventory &&
                  _initialStockController.text.trim().isNotEmpty
              ? _initialStockController.text.trim().replaceAll(',', '.')
              : null,
          recipeComponents: _recipeEnabled
              ? List.unmodifiable(_recipeComponents)
              : const [],
        ),
      ),
    );
  }

  Future<void> _openRecipeEditor() async {
    final repository = widget.inventoryResourceRepository;
    final onCreate = widget.onCreateInventoryResource;
    if (repository == null || onCreate == null) return;
    final result = await Navigator.of(context)
        .push<List<RecipeComponentFormResult>>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => RecipeEditorScreen(
              repository: repository,
              units: widget.inventoryUnits,
              initialValue: _recipeComponents,
              onCreateInventoryResource: onCreate,
            ),
          ),
        );
    if (result == null || !mounted) return;
    setState(() {
      _recipeComponents = List.of(result);
      _recipeError = null;
    });
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
      final rounded = (absolute + denominator ~/ BigInt.from(2)) ~/ denominator;
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

class _EditorCard extends StatelessWidget {
  const _EditorCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(4),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _CompactMoneyField extends StatelessWidget {
  const _CompactMoneyField({
    required this.columnKey,
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.textInputAction,
    required this.validator,
    this.signed = false,
    this.onFieldSubmitted,
  });

  final Key columnKey;
  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final FormFieldValidator<String> validator;
  final bool signed;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      key: columnKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, maxLines: 2, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        TextFormField(
          key: fieldKey,
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(
            decimal: true,
            signed: signed,
          ),
          inputFormatters: const [CurrencyInputFormatter()],
          textInputAction: textInputAction,
          decoration: InputDecoration(
            hintText: '0.00',
            isDense: true,
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            border: const OutlineInputBorder(borderSide: BorderSide.none),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide.none,
            ),
            errorMaxLines: 3,
          ),
          validator: validator,
          onFieldSubmitted: onFieldSubmitted,
        ),
      ],
    );
  }
}

class _CompactReadOnlyValue extends StatelessWidget {
  const _CompactReadOnlyValue({
    required this.label,
    required this.value,
    required this.valueKey,
    super.key,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, maxLines: 2, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(value, key: valueKey),
        ),
      ],
    );
  }
}
