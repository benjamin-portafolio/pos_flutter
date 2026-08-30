import 'package:flutter/material.dart';

import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../domain/inventario/nombre_recurso_inventario.dart';
import '../../../../domain/inventario/recurso_inventario_listado.dart';
import '../../../../domain/inventario/tipo_movimiento_inventario.dart';
import '../../../../domain/inventario/unidad_inventario.dart';
import 'models/inventory_resource_form_result.dart';
import 'widgets/inventory_quantity_input_formatter.dart';
import 'widgets/inventory_unit_picker.dart';

enum _AdjustmentDirection { add, remove }

class InventoryResourceFormScreen extends StatefulWidget {
  const InventoryResourceFormScreen({
    required this.units,
    required this.onSave,
    super.key,
  }) : resource = null;

  const InventoryResourceFormScreen.edit({
    required this.resource,
    required this.onSave,
    super.key,
  }) : units = const [];

  final List<UnidadInventario> units;
  final Future<void> Function(InventoryResourceFormResult result) onSave;
  final RecursoInventarioListado? resource;

  @override
  State<InventoryResourceFormScreen> createState() =>
      _InventoryResourceFormScreenState();
}

class _InventoryResourceFormScreenState
    extends State<InventoryResourceFormScreen> {
  static const _codec = InventoryQuantityCodec();
  static const _receiptReasons = <String>[
    'Sin motivo',
    'Compra',
    'Devolución',
    'Transferencia',
    'Otro',
  ];
  static const _adjustmentReasons = <String>[
    'Seleccionar motivo',
    'Conteo físico',
    'Error de captura',
    'Daño o merma',
    'Uso interno',
    'Otro',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  UnidadInventario? _selectedUnit;
  TipoMovimientoInventario _movementType =
      TipoMovimientoInventario.stockReceipt;
  _AdjustmentDirection _direction = _AdjustmentDirection.add;
  String _reasonChoice = 'Sin motivo';
  bool _saving = false;
  bool _canPop = false;
  String? _saveError;

  bool get _editing => widget.resource != null;

  @override
  void initState() {
    super.initState();
    final resource = widget.resource;
    if (resource == null) return;
    _nameController.text = resource.nombre;
    _selectedUnit = resource.unidadPredeterminada;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope<bool>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _saving ? null : _requestClose,
            icon: const Icon(Icons.close),
            tooltip: 'Cancelar',
          ),
          title: Text(
            _editing
                ? 'Editar recurso de inventario'
                : 'Nuevo recurso de inventario',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                key: const Key('save_inventory_resource_button'),
                onPressed: _saving ? null : _submit,
                style: TextButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                icon: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('GUARDAR'),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFF2F3F5),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Detalles',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _FormCard(
                    child: TextFormField(
                      key: const Key('inventory_resource_name_field'),
                      controller: _nameController,
                      enabled: !_saving,
                      maxLength: 160,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        hintText: 'Ej. Harina',
                        border: InputBorder.none,
                        counterText: '',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: _validateName,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildUnitField(colorScheme),
                  const SizedBox(height: 24),
                  Text(
                    _editing ? 'Registrar movimiento' : 'Existencia inicial',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_editing) ...[
                    _buildMovementTypeSelector(),
                    const SizedBox(height: 12),
                  ],
                  if (_editing &&
                      _movementType ==
                          TipoMovimientoInventario.manualAdjustment) ...[
                    _buildDirectionSelector(),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _BalancePreviewCard(
                          key: const Key('inventory_current_balance'),
                          label: 'Existencia actual',
                          value: _currentBalance,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BalancePreviewCard(
                          key: const Key('inventory_updated_balance'),
                          label: 'Existencia resultante',
                          value: _updatedBalance,
                          valueColor: _directionColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FormCard(
                    child: TextFormField(
                      key: const Key('inventory_initial_quantity_field'),
                      controller: _quantityController,
                      enabled: !_saving && _selectedUnit != null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: false,
                      ),
                      inputFormatters: [
                        InventoryQuantityInputFormatter(
                          _selectedUnit?.maximosDecimales ?? 0,
                        ),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _editing
                            ? 'Cantidad del movimiento (opcional)'
                            : 'Cantidad inicial (opcional)',
                        hintText: _selectedUnit == null
                            ? 'Elige una unidad'
                            : '0',
                        border: InputBorder.none,
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _signedPrefix,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: _directionColor,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        suffixText: _selectedUnit?.simbolo,
                      ),
                      validator: _validateQuantity,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_editing)
                    _buildReasonSelector()
                  else
                    _buildCustomReasonField(
                      label: 'Motivo de existencia inicial (opcional)',
                    ),
                  if (_saveError != null) ...[
                    const SizedBox(height: 16),
                    Material(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _saveError!,
                          key: const Key('inventory_resource_save_error'),
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnitField(ColorScheme colorScheme) {
    return _FormCard(
      child: FormField<UnidadInventario>(
        key: const Key('inventory_default_unit_field'),
        initialValue: _selectedUnit,
        validator: (value) =>
            value == null ? 'Selecciona una unidad predeterminada.' : null,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.straighten),
              title: const Text('Unidad predeterminada *'),
              subtitle: Text(
                _selectedUnit == null
                    ? 'Seleccionar unidad'
                    : '${_selectedUnit!.nombre} (${_selectedUnit!.simbolo})',
              ),
              trailing: _editing
                  ? const Icon(Icons.lock_outline)
                  : const Icon(Icons.expand_more),
              onTap: _editing || _saving
                  ? null
                  : () async {
                      final selected = await InventoryUnitPicker.show(
                        context: context,
                        units: widget.units,
                        selected: _selectedUnit,
                      );
                      if (selected == null || !mounted) return;
                      setState(() {
                        _selectedUnit = selected;
                        _quantityController.clear();
                      });
                      field.didChange(selected);
                    },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _editing
                    ? 'La unidad no puede cambiarse porque el historial ya utiliza esta unidad.'
                    : 'Se usará para capturar y mostrar las existencias.',
              ),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  field.errorText!,
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementTypeSelector() {
    return SegmentedButton<TipoMovimientoInventario>(
      key: const Key('inventory_movement_type'),
      segments: const [
        ButtonSegment(
          value: TipoMovimientoInventario.stockReceipt,
          label: Text('Agregar existencia'),
          icon: Icon(Icons.add_box_outlined),
        ),
        ButtonSegment(
          value: TipoMovimientoInventario.manualAdjustment,
          label: Text('Corregir existencia'),
          icon: Icon(Icons.tune),
        ),
      ],
      selected: {_movementType},
      onSelectionChanged: _saving
          ? null
          : (selection) => setState(() {
              _movementType = selection.single;
              _direction = _AdjustmentDirection.add;
              _reasonChoice =
                  _movementType == TipoMovimientoInventario.stockReceipt
                  ? 'Sin motivo'
                  : 'Seleccionar motivo';
              _reasonController.clear();
            }),
    );
  }

  Widget _buildDirectionSelector() {
    return SegmentedButton<_AdjustmentDirection>(
      key: const Key('inventory_stock_direction'),
      segments: const [
        ButtonSegment(
          value: _AdjustmentDirection.add,
          label: Text('Aumentar (+)'),
          icon: Icon(Icons.add),
        ),
        ButtonSegment(
          value: _AdjustmentDirection.remove,
          label: Text('Disminuir (−)'),
          icon: Icon(Icons.remove),
        ),
      ],
      selected: {_direction},
      onSelectionChanged: _saving
          ? null
          : (selection) => setState(() => _direction = selection.single),
    );
  }

  Widget _buildReasonSelector() {
    final reasons = _movementType == TipoMovimientoInventario.stockReceipt
        ? _receiptReasons
        : _adjustmentReasons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormCard(
          child: DropdownButtonFormField<String>(
            key: const Key('inventory_movement_reason_choice'),
            initialValue: _reasonChoice,
            decoration: InputDecoration(
              labelText: _movementType == TipoMovimientoInventario.stockReceipt
                  ? 'Motivo (opcional)'
                  : 'Motivo *',
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.notes),
            ),
            items: reasons
                .map(
                  (reason) =>
                      DropdownMenuItem(value: reason, child: Text(reason)),
                )
                .toList(growable: false),
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    _reasonChoice = value!;
                    _reasonController.clear();
                  }),
            validator: (_) => _validateReason(),
          ),
        ),
        if (_reasonChoice == 'Otro') ...[
          const SizedBox(height: 12),
          _buildCustomReasonField(label: 'Especifica el motivo *'),
        ],
      ],
    );
  }

  Widget _buildCustomReasonField({required String label}) {
    return _FormCard(
      child: TextFormField(
        key: const Key('inventory_movement_reason_field'),
        controller: _reasonController,
        enabled: !_saving,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          counterText: '',
          prefixIcon: const Icon(Icons.edit_note),
        ),
        validator: (_) =>
            _editing ? _validateReason() : _validateOptionalReason(),
      ),
    );
  }

  String get _currentBalance {
    final unit = _selectedUnit;
    if (unit == null) return '—';
    final current = widget.resource?.existenciaAtomica ?? 0;
    return '${_codec.formatAtomic(current, unit)} ${unit.simbolo}';
  }

  String get _updatedBalance {
    final unit = _selectedUnit;
    final raw = _quantityController.text.trim();
    if (unit == null || raw.isEmpty) return _currentBalance;
    try {
      final magnitude = _codec.parsePositiveAtomic(raw, unit);
      final delta = _direction == _AdjustmentDirection.add
          ? magnitude
          : -magnitude;
      final result = (widget.resource?.existenciaAtomica ?? 0) + delta;
      return '${_codec.formatAtomic(result, unit)} ${unit.simbolo}';
    } on FormatException {
      return '—';
    }
  }

  String get _signedPrefix =>
      _direction == _AdjustmentDirection.add ? '+' : '−';

  Color get _directionColor => _direction == _AdjustmentDirection.add
      ? const Color(0xFF2E7D32)
      : const Color(0xFFC62828);

  String? _validateName(String? value) {
    try {
      NombreRecursoInventario.fromInput(value ?? '');
      return null;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? 'Nombre inválido.';
    }
  }

  String? _validateQuantity(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final unit = _selectedUnit;
    if (unit == null) return 'Selecciona una unidad.';
    try {
      _codec.parsePositiveAtomic(raw, unit);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validateReason() {
    if (_quantityController.text.trim().isEmpty) return null;
    if (_movementType == TipoMovimientoInventario.manualAdjustment &&
        _reasonChoice == 'Seleccionar motivo') {
      return 'Selecciona un motivo para la corrección manual.';
    }
    if (_reasonChoice == 'Otro' && _reasonController.text.trim().isEmpty) {
      return 'Especifica el motivo.';
    }
    return _validateOptionalReason();
  }

  String? _validateOptionalReason() {
    final reason = _reasonController.text.trim();
    if (reason.runes.length > 500) {
      return 'El motivo no puede exceder 500 caracteres.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final unit = _selectedUnit!;
    final rawQuantity = _quantityController.text.trim();
    final magnitude = rawQuantity.isEmpty
        ? null
        : _codec.parsePositiveAtomic(rawQuantity, unit);
    final delta = magnitude == null
        ? null
        : _direction == _AdjustmentDirection.add
        ? magnitude
        : -magnitude;
    final movementType = delta == null
        ? null
        : _editing
        ? _movementType
        : TipoMovimientoInventario.initialBalance;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(
        InventoryResourceFormResult(
          nombre: _nameController.text,
          unidad: unit,
          quantityDeltaAtomic: delta,
          movementReason: delta == null ? null : _selectedReason,
          movementType: movementType,
        ),
      );
      if (!mounted) return;
      setState(() => _canPop = true);
      await Future<void>.delayed(Duration.zero);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'No se pudo guardar el recurso de inventario.';
      });
    }
  }

  String? get _selectedReason {
    if (!_editing) {
      final value = _reasonController.text.trim();
      return value.isEmpty ? null : value;
    }
    if (_reasonChoice == 'Sin motivo' ||
        _reasonChoice == 'Seleccionar motivo') {
      return null;
    }
    if (_reasonChoice == 'Otro') return _reasonController.text;
    return _reasonChoice;
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_hasChanges) {
      setState(() => _canPop = true);
      await Future<void>.delayed(Duration.zero);
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar cambios'),
        content: const Text('Hay datos sin guardar. ¿Quieres descartarlos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CONTINUAR EDITANDO'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DESCARTAR'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => _canPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) Navigator.of(context).pop(false);
  }

  bool get _hasChanges {
    final resource = widget.resource;
    if (resource == null) {
      return _nameController.text.isNotEmpty ||
          _selectedUnit != null ||
          _quantityController.text.isNotEmpty ||
          _reasonController.text.isNotEmpty;
    }
    return _nameController.text != resource.nombre ||
        _quantityController.text.isNotEmpty ||
        _reasonController.text.isNotEmpty ||
        _movementType != TipoMovimientoInventario.stockReceipt ||
        _direction != _AdjustmentDirection.add ||
        _reasonChoice != 'Sin motivo';
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: child,
      ),
    );
  }
}

class _BalancePreviewCard extends StatelessWidget {
  const _BalancePreviewCard({
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          children: [
            Text(label, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
