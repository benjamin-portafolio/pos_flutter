import 'package:flutter/material.dart';

import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../domain/inventario/nombre_recurso_inventario.dart';
import '../../../../domain/inventario/recurso_inventario_listado.dart';
import '../../../../domain/inventario/unidad_inventario.dart';
import 'models/inventory_resource_form_result.dart';
import 'widgets/inventory_quantity_input_formatter.dart';
import 'widgets/inventory_unit_picker.dart';

enum _StockDirection { add, remove }

class InventoryResourceFormScreen extends StatefulWidget {
  const InventoryResourceFormScreen({
    required this.units,
    required this.onSave,
    super.key,
  }) : resource = null;

  const InventoryResourceFormScreen.readOnly({
    required this.resource,
    super.key,
  }) : units = const [],
       onSave = null;

  final List<UnidadInventario> units;
  final Future<void> Function(InventoryResourceFormResult result)? onSave;
  final RecursoInventarioListado? resource;

  @override
  State<InventoryResourceFormScreen> createState() =>
      _InventoryResourceFormScreenState();
}

class _InventoryResourceFormScreenState
    extends State<InventoryResourceFormScreen> {
  static const _codec = InventoryQuantityCodec();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController(text: 'Existencia inicial');
  UnidadInventario? _selectedUnit;
  _StockDirection _direction = _StockDirection.add;
  bool _saving = false;
  bool _canPop = false;
  String? _saveError;

  bool get _readOnly => widget.resource != null;

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
      canPop: _readOnly || _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _saving ? null : _requestClose,
            icon: Icon(_readOnly ? Icons.arrow_back : Icons.close),
            tooltip: _readOnly ? 'Regresar' : 'Cancelar',
          ),
          title: Text(_readOnly ? 'RECURSO DE INVENTARIO' : 'AÑADIR RECURSO'),
          actions: _readOnly
              ? const []
              : [
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
                      enabled: !_readOnly && !_saving,
                      maxLength: 160,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: _readOnly ? 'Nombre' : 'Nombre *',
                        hintText: 'Ej. Harina',
                        border: InputBorder.none,
                        counterText: '',
                        prefixIcon: const Icon(Icons.inventory_2_outlined),
                      ),
                      validator: _readOnly ? null : _validateName,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FormCard(
                    child: FormField<UnidadInventario>(
                      key: const Key('inventory_default_unit_field'),
                      initialValue: _selectedUnit,
                      validator: _readOnly
                          ? null
                          : (value) => value == null
                                ? 'Selecciona una unidad predeterminada.'
                                : null,
                      builder: (field) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.straighten),
                            title: Text(
                              _readOnly
                                  ? 'Unidad predeterminada'
                                  : 'Unidad predeterminada *',
                            ),
                            subtitle: Text(
                              _selectedUnit == null
                                  ? 'Seleccionar unidad'
                                  : '${_selectedUnit!.nombre} (${_selectedUnit!.simbolo})',
                            ),
                            trailing: _readOnly
                                ? null
                                : const Icon(Icons.expand_more),
                            onTap: _readOnly || _saving
                                ? null
                                : () async {
                                    final selected =
                                        await InventoryUnitPicker.show(
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
                              _readOnly
                                  ? 'Se usa para mostrar las existencias.'
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
                  ),
                  if (_readOnly)
                    ..._buildReadOnlyInventory(context)
                  else ...[
                    const SizedBox(height: 24),
                    Text(
                      'Existencias iniciales',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _buildDirectionSelector(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _BalancePreviewCard(
                            label: 'Existencias actuales',
                            value: _withSymbol('0'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BalancePreviewCard(
                            key: const Key('inventory_updated_balance'),
                            label: 'Existencias actualizadas',
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
                          labelText: 'Cantidad inicial (opcional)',
                          hintText: _selectedUnit == null
                              ? 'Elige una unidad'
                              : '0',
                          border: InputBorder.none,
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _direction == _StockDirection.add ? '+' : '−',
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
                    _FormCard(
                      child: TextFormField(
                        key: const Key('inventory_movement_reason_field'),
                        controller: _reasonController,
                        enabled: !_saving,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Motivo del movimiento',
                          border: InputBorder.none,
                          counterText: '',
                          prefixIcon: Icon(Icons.notes),
                        ),
                        validator: _validateReason,
                      ),
                    ),
                  ],
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

  Widget _buildDirectionSelector() {
    return SegmentedButton<_StockDirection>(
      key: const Key('inventory_stock_direction'),
      segments: const [
        ButtonSegment(
          value: _StockDirection.add,
          label: Text('Añadir existencias (+)', textAlign: TextAlign.center),
          icon: Icon(Icons.add),
        ),
        ButtonSegment(
          value: _StockDirection.remove,
          label: Text('Eliminar stock (−)', textAlign: TextAlign.center),
          icon: Icon(Icons.remove),
        ),
      ],
      selected: {_direction},
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.selected)) return null;
          return _directionColor;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return Theme.of(context).colorScheme.primary;
        }),
      ),
      onSelectionChanged: _saving
          ? null
          : (selection) => setState(() => _direction = selection.single),
    );
  }

  List<Widget> _buildReadOnlyInventory(BuildContext context) {
    final resource = widget.resource!;
    final unit = resource.unidadPredeterminada;
    final quantity = _codec.formatAtomic(resource.existenciaAtomica, unit);
    return [
      const SizedBox(height: 24),
      Text('Existencias', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _BalancePreviewCard(
        key: const Key('inventory_current_balance'),
        label: 'Existencias actuales',
        value: '$quantity ${unit.simbolo}',
        valueColor: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 12),
      _FormCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            resource.activo ? Icons.check_circle_outline : Icons.block,
          ),
          title: const Text('Estado'),
          subtitle: Text(resource.activo ? 'Activo' : 'Inactivo'),
        ),
      ),
    ];
  }

  Color get _directionColor => _direction == _StockDirection.add
      ? const Color(0xFF2E7D32)
      : const Color(0xFFC62828);

  String get _updatedBalance {
    final unit = _selectedUnit;
    final raw = _quantityController.text.trim();
    if (unit == null || raw.isEmpty) return '—';
    try {
      final magnitude = _codec.parsePositiveAtomic(raw, unit);
      final atomic = _direction == _StockDirection.add ? magnitude : -magnitude;
      return _withSymbol(_codec.formatAtomic(atomic, unit));
    } on FormatException {
      return '—';
    }
  }

  String _withSymbol(String value) {
    final symbol = _selectedUnit?.simbolo;
    return symbol == null ? value : '$value $symbol';
  }

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

  String? _validateReason(String? value) {
    if (_quantityController.text.trim().isEmpty) return null;
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'El motivo es obligatorio cuando capturas una cantidad.';
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
        : _direction == _StockDirection.add
        ? magnitude
        : -magnitude;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave!(
        InventoryResourceFormResult(
          nombre: _nameController.text,
          unidad: unit,
          quantityDeltaAtomic: delta,
          movementReason: delta == null ? null : _reasonController.text,
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

  Future<void> _requestClose() async {
    if (_saving) return;
    if (_readOnly) {
      Navigator.of(context).pop(false);
      return;
    }
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

  bool get _hasChanges =>
      _nameController.text.isNotEmpty ||
      _selectedUnit != null ||
      _quantityController.text.isNotEmpty;
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
