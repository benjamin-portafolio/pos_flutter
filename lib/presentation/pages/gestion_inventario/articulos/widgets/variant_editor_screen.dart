import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../domain/articulos/codigo_barras.dart';
import '../../../../../domain/articulos/costo_estandar.dart';
import '../../../../../domain/articulos/nombre_variante.dart';
import '../../../../../domain/articulos/precio_venta.dart';
import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../../domain/inventario/recurso_inventario_listado.dart';
import '../../../../../domain/inventario/unidad_inventario.dart';
import '../../../../../domain/repositories/recurso_inventario_repository.dart';
import '../../recursos/inventory_movement_screen.dart';
import '../../recursos/models/inventory_movement_draft.dart';
import '../../recursos/models/inventory_resource_form_result.dart';
import '../../recursos/widgets/inventory_quantity_input_formatter.dart';
import '../models/articulo_form_result.dart';
import '../models/recipe_component_form_result.dart';
import 'barcode_scanner_screen.dart';
import 'currency_input_formatter.dart';
import 'recipe_editor_screen.dart';

class VariantEditorScreen extends StatefulWidget {
  const VariantEditorScreen({
    required this.initialValue,
    this.preview = false,
    required this.canDelete,
    this.isLastVariant = false,
    required this.existingNameKeys,
    required this.inventoryUnit,
    this.inventoryUnits = const [],
    this.inventoryResourceRepository,
    this.onCreateInventoryResource,
    this.onRegisterInventoryMovement,
    this.productName,
    super.key,
  });

  final ArticuloFormVarianteResult? initialValue;
  final bool preview;
  final bool canDelete;
  final bool isLastVariant;
  final Set<String> existingNameKeys;
  final UnidadInventario inventoryUnit;
  final List<UnidadInventario> inventoryUnits;
  final RecursoInventarioRepository? inventoryResourceRepository;
  final Future<void> Function(InventoryResourceFormResult result)?
  onCreateInventoryResource;

  /// Registra un movimiento sobre el recurso ya vinculado de la variante. Es
  /// independiente del guardado del artículo y no transporta nombre ni unidad.
  final Future<void> Function(String inventoryItemId, InventoryMovementDraft)?
  onRegisterInventoryMovement;

  /// Nombre del artículo, para identificar el recurso en la pantalla de
  /// movimientos. Es texto de consulta, no un dato editable.
  final String? productName;

  @override
  State<VariantEditorScreen> createState() => _VariantEditorScreenState();
}

class _VariantEditorScreenState extends State<VariantEditorScreen> {
  static const _saveColor = Color(0xFF4CAF50);
  static const _codec = InventoryQuantityCodec();

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;
  late final TextEditingController _initialStockController;
  late bool _trackingInventory;
  late bool _recipeEnabled;
  late List<RecipeComponentFormResult> _recipeComponents;
  String? _recipeError;
  String? _barcodeError;
  StreamSubscription<RecursoInventarioListado?>? _linkedResourceSubscription;
  RecursoInventarioListado? _linkedResource;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _watchLinkedResource(initial?.linkedInventoryItemId);
    _nameController = TextEditingController(text: initial?.nombre ?? '');
    _barcodeController = TextEditingController(
      text: initial?.codigoBarras ?? '',
    );
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
    _barcodeController.addListener(_clearBarcodeError);
  }

  /// Observa el recurso ya vinculado para mostrar su saldo vigente.
  ///
  /// El id viene del resultado del formulario de artículo: identifica el
  /// recurso, no es una intención de cambio. Sin enlace no hay nada que
  /// observar y la variante sigue capturando existencia inicial.
  void _watchLinkedResource(String? inventoryItemId) {
    final repository = widget.inventoryResourceRepository;
    if (inventoryItemId == null || repository == null) return;
    _linkedResourceSubscription = repository
        .watchRecursoPorId(inventoryItemId)
        .listen(
          (resource) {
            if (!mounted) return;
            setState(() => _linkedResource = resource);
          },
          onError: (Object error) {
            if (mounted) setState(() => _linkedResource = null);
          },
        );
  }

  @override
  void dispose() {
    _linkedResourceSubscription?.cancel();
    _priceController.removeListener(_refreshCalculatedValues);
    _costController.removeListener(_refreshCalculatedValues);
    _barcodeController.removeListener(_clearBarcodeError);
    _nameController.dispose();
    _barcodeController.dispose();
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
                onPressed: widget.canDelete && !widget.preview
                    ? _confirmDelete
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
                onPressed: widget.preview ? null : _save,
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
                    readOnly: widget.preview,
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
                  child: Column(
                    key: const Key('variant_barcode_card'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: Text('¿Código de barras?')),
                          Tooltip(
                            message:
                                'Solo dígitos, hasta '
                                '${CodigoBarras.maxLength} caracteres. '
                                'Se guarda como texto para conservar los ceros '
                                'a la izquierda.',
                            child: Icon(
                              Icons.help_outline,
                              key: const Key('variant_barcode_help_icon'),
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('variant_barcode_field'),
                              controller: _barcodeController,
                              readOnly: widget.preview,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                hintText: 'Ej. 750802876102',
                                counterText: '',
                                border: InputBorder.none,
                              ),
                              validator: _validateBarcode,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Flexible para que en pantallas angostas el botón
                          // en vez de desbordar la fila con el campo.
                          Flexible(
                            child: FilledButton.tonal(
                              key: const Key('scan_barcode_button'),
                              onPressed: widget.preview
                                  ? null
                                  : _openBarcodeScanner,
                              child: const Text(
                                'ESCANEAR',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_barcodeError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _barcodeError!,
                          key: const Key('variant_barcode_error'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.error),
                        ),
                      ],
                    ],
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
                          readOnly: widget.preview,
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
                          readOnly: widget.preview,
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
                        onChanged: widget.preview
                            ? null
                            : (value) => setState(() {
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
                      if (_trackingInventory &&
                          (_linkedItemId != null || !widget.preview)) ...[
                        const Divider(),
                        if (_linkedItemId != null)
                          _buildLinkedInventoryResource()
                        else
                          _buildInitialStockField(),
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
                            widget.preview ||
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
                        onPressed: _recipeEnabled && !widget.preview
                            ? _openRecipeEditor
                            : null,
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

  /// Recurso de inventario persistido y vinculado a la variante.
  String? get _linkedItemId => widget.initialValue?.linkedInventoryItemId;

  Widget _buildInitialStockField() {
    return TextFormField(
      key: const Key('variant_initial_stock_field'),
      controller: _initialStockController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        InventoryQuantityInputFormatter(widget.inventoryUnit.maximosDecimales),
      ],
      decoration: InputDecoration(
        labelText: 'Existencia inicial (opcional)',
        suffixText: widget.inventoryUnit.simbolo,
        helperText:
            'Se registrará como movimiento inicial; el saldo comienza en cero si queda vacío.',
        border: InputBorder.none,
      ),
      validator: _validateInitialStock,
    );
  }

  /// Bloque de la variante con recurso ya vinculado: saldo vigente y acceso al
  /// registro de movimientos. No captura existencia inicial porque el recurso
  /// ya existe y su saldo lo mueven los eventos de inventario.
  Widget _buildLinkedInventoryResource() {
    final colorScheme = Theme.of(context).colorScheme;
    final resource = _linkedResource;
    final unit = resource?.unidadPredeterminada ?? widget.inventoryUnit;
    return Column(
      key: const Key('variant_linked_inventory_resource'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Existencia actual',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (resource != null)
              Text(
                '${_codec.formatAtomic(resource.existenciaAtomica, unit)} '
                '${unit.simbolo}',
                key: const Key('variant_linked_inventory_balance'),
                style: Theme.of(context).textTheme.titleMedium,
              )
            else
              Text('—', key: const Key('variant_linked_inventory_balance')),
          ],
        ),
        if (!widget.preview) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('register_inventory_movement_button'),
            onPressed:
                widget.onRegisterInventoryMovement == null ||
                    widget.inventoryResourceRepository == null ||
                    resource == null
                ? null
                : _openInventoryMovement,
            icon: const Icon(Icons.swap_vert),
            label: const Text('REGISTRAR MOVIMIENTO'),
          ),
          const SizedBox(height: 8),
          Text(
            'El movimiento se registra de forma independiente y permanece aunque '
            'canceles el guardado de la variante.',
            key: const Key('variant_inventory_movement_note'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Abre el registro de movimientos del recurso vinculado.
  ///
  /// El saldo mostrado en el editor se refresca solo por la suscripción al
  /// recurso, así que al volver no hay que copiar nada a mano.
  Future<void> _openInventoryMovement() async {
    if (widget.preview) return;
    final repository = widget.inventoryResourceRepository;
    final inventoryItemId = _linkedItemId;
    final register = widget.onRegisterInventoryMovement;
    if (repository == null || inventoryItemId == null || register == null) {
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => InventoryMovementScreen(
          repository: repository,
          inventoryItemId: inventoryItemId,
          resourceLabel: _resourceLabel,
          onRegister: (movement) => register(inventoryItemId, movement),
        ),
      ),
    );
  }

  /// Texto de consulta para identificar la variante en la pantalla de
  /// movimientos. No es un dato editable del recurso.
  String get _resourceLabel {
    final name = _nameController.text.trim();
    final product = widget.productName?.trim() ?? '';
    if (name.isEmpty) return product.isEmpty ? 'Variante' : product;
    return product.isEmpty ? name : '$product · $name';
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete_variant_dialog'),
        scrollable: true,
        icon: const Icon(Icons.delete_forever),
        title: Text(
          widget.isLastVariant
              ? '¿Eliminar la última variante y el producto?'
              : '¿Eliminar esta variante?',
        ),
        content: Text(
          '${widget.isLastVariant ? 'También se eliminará el producto. ' : ''}'
          'Se conservarán los registros que tengan dependencias para mantener el historial. '
          'El cambio se aplicará al guardar el artículo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('NO'),
          ),
          TextButton(
            key: const Key('confirm_delete_variant_button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const VariantEditorResult.deleted());
    }
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

  String? _validateBarcode(String? value) {
    try {
      CodigoBarras.fromInput(value);
      return null;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? 'Código de barras inválido.';
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
    if (widget.preview) return;
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
          id: widget.initialValue?.id,
          nombre: name.value,
          precioVenta: _priceController.text.trim().replaceAll(',', '.'),
          costoEstandar: CostoEstandar.fromInput(_costController.text) == null
              ? null
              : _costController.text.trim().replaceAll(',', '.'),
          codigoBarras: CodigoBarras.fromInput(_barcodeController.text).value,
          inventoryUnitId: _trackingInventory ? widget.inventoryUnit.id : null,
          existenciaInicial:
              _trackingInventory &&
                  _linkedItemId == null &&
                  _initialStockController.text.trim().isNotEmpty
              ? _initialStockController.text.trim().replaceAll(',', '.')
              : null,
          // La identidad del recurso vinculado sobrevive al guardado del
          // artículo: no es un cambio, solo evita perder el enlace al reconstruir
          // el resultado de la variante.
          linkedInventoryItemId: _linkedItemId,
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

  void _clearBarcodeError() {
    if (_barcodeError == null) return;
    setState(() => _barcodeError = null);
  }

  /// Abre la pantalla de escaneo y aplica el valor devuelto al campo.
  ///
  /// El valor NO se persiste acá: solo se setea el controller y lo guarda
  /// `_save()`, igual que una captura manual, para que el camino de guardado
  /// sea uno solo. `null` significa que el usuario canceló con el `X`.
  Future<void> _openBarcodeScanner() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const BarcodeScannerScreen(),
      ),
    );
    if (barcode == null || !mounted) return;
    // El value object decide ANTES de aceptar el valor: un lector puede
    // devolver algo que no es dígito, y ese error tiene que verse en el
    // formulario en vez de tragarse el código en silencio.
    try {
      CodigoBarras.fromInput(barcode);
    } on ArgumentError catch (error) {
      setState(() {
        _barcodeError =
            error.message?.toString() ?? 'Código de barras inválido.';
      });
      return;
    }
    _barcodeController.text = barcode;
  }

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
    this.readOnly = false,
    this.onFieldSubmitted,
  });

  final Key columnKey;
  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final FormFieldValidator<String> validator;
  final bool signed;
  final bool readOnly;
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
          readOnly: readOnly,
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
