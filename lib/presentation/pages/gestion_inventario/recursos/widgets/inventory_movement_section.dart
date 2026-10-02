import 'package:flutter/material.dart';

import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../../domain/inventario/tipo_movimiento_inventario.dart';
import '../../../../../domain/inventario/unidad_inventario.dart';
import '../models/inventory_movement_draft.dart';
import 'inventory_form_card.dart';
import 'inventory_quantity_input_formatter.dart';

/// Cómo se interpreta la cantidad capturada en la sección.
enum InventoryMovementSectionMode {
  /// Existencia inicial de un recurso que todavía no existe. La cantidad es un
  /// saldo inicial positivo y el motivo es opcional.
  initialBalance,

  /// Movimiento sobre un recurso existente: reposición o corrección manual, con
  /// dirección y motivo según el tipo.
  movement,
}

/// Sección de movimientos reutilizada por el formulario de recursos de
/// inventario y por el registro de movimientos desde el editor de variantes.
///
/// La sección es dueña de sus controles y de sus validaciones: el contenedor
/// la valida con [validate], lee el resultado capturado con [readDraft] y
/// consulta [hasPendingChanges] para detectar datos sin guardar.
class InventoryMovementSection extends StatefulWidget {
  const InventoryMovementSection({
    required this.mode,
    required this.currentBalanceAtomic,
    this.unit,
    this.busy = false,
    this.quantityRequired = false,
    super.key,
  });

  final InventoryMovementSectionMode mode;

  /// Saldo vigente del recurso. La existencia resultante es una previsión.
  final int currentBalanceAtomic;

  /// Unidad del recurso. `null` mientras no se haya elegido una.
  final UnidadInventario? unit;

  /// El contenedor está guardando: la sección queda bloqueada.
  final bool busy;

  /// El registro independiente exige un movimiento; editar un recurso permite
  /// guardar solo su nombre sin capturar cantidad.
  final bool quantityRequired;

  @override
  State<InventoryMovementSection> createState() =>
      InventoryMovementSectionState();
}

enum _AdjustmentDirection { add, remove }

class InventoryMovementSectionState extends State<InventoryMovementSection> {
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
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  TipoMovimientoInventario _movementType =
      TipoMovimientoInventario.stockReceipt;
  _AdjustmentDirection _direction = _AdjustmentDirection.add;
  String _reasonChoice = 'Sin motivo';

  bool get _isMovement => widget.mode == InventoryMovementSectionMode.movement;

  @override
  void didUpdateWidget(InventoryMovementSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // La cantidad pertenece a la unidad capturada: cambiarla descarta lo
    // escrito, igual que en el formulario de recursos.
    if (widget.unit?.id != oldWidget.unit?.id) _quantityController.clear();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  /// Valida cantidad y motivo de la sección.
  bool validate() => _formKey.currentState?.validate() ?? false;

  /// Movimiento capturado, o `null` cuando no hay cantidad.
  InventoryMovementDraft? readDraft() {
    final unit = widget.unit;
    final raw = _quantityController.text.trim();
    if (unit == null || raw.isEmpty) return null;
    final magnitude = _codec.parsePositiveAtomic(raw, unit);
    return InventoryMovementDraft(
      movementType: _isMovement
          ? _movementType
          : TipoMovimientoInventario.initialBalance,
      quantityDeltaAtomic: _direction == _AdjustmentDirection.add
          ? magnitude
          : -magnitude,
      reason: _selectedReason,
    );
  }

  /// Hay datos capturados que se perderían al cerrar sin guardar.
  bool get hasPendingChanges {
    if (_quantityController.text.isNotEmpty ||
        _reasonController.text.isNotEmpty) {
      return true;
    }
    if (!_isMovement) return false;
    return _movementType != TipoMovimientoInventario.stockReceipt ||
        _direction != _AdjustmentDirection.add ||
        _reasonChoice != 'Sin motivo';
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isMovement) ...[
            _buildMovementTypeSelector(),
            const SizedBox(height: 12),
          ],
          if (_isMovement &&
              _movementType == TipoMovimientoInventario.manualAdjustment) ...[
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
          InventoryFormCard(
            child: TextFormField(
              key: const Key('inventory_initial_quantity_field'),
              controller: _quantityController,
              enabled: !widget.busy && unit != null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              inputFormatters: [
                InventoryQuantityInputFormatter(unit?.maximosDecimales ?? 0),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isMovement
                    ? widget.quantityRequired
                          ? 'Cantidad del movimiento *'
                          : 'Cantidad del movimiento (opcional)'
                    : 'Cantidad inicial (opcional)',
                hintText: unit == null ? 'Elige una unidad' : '0',
                border: InputBorder.none,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _signedPrefix,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _directionColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                suffixText: unit?.simbolo,
              ),
              validator: _validateQuantity,
            ),
          ),
          const SizedBox(height: 12),
          _isMovement
              ? _buildReasonSelector()
              : _buildCustomReasonField(
                  label: 'Motivo de existencia inicial (opcional)',
                ),
        ],
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
      onSelectionChanged: widget.busy
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
      onSelectionChanged: widget.busy
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
        InventoryFormCard(
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
            onChanged: widget.busy
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
    return InventoryFormCard(
      child: TextFormField(
        key: const Key('inventory_movement_reason_field'),
        controller: _reasonController,
        enabled: !widget.busy,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          counterText: '',
          prefixIcon: const Icon(Icons.edit_note),
        ),
        validator: (_) =>
            _isMovement ? _validateReason() : _validateOptionalReason(),
      ),
    );
  }

  String get _currentBalance {
    final unit = widget.unit;
    if (unit == null) return '—';
    return '${_codec.formatAtomic(widget.currentBalanceAtomic, unit)} ${unit.simbolo}';
  }

  String get _updatedBalance {
    final unit = widget.unit;
    final raw = _quantityController.text.trim();
    if (unit == null || raw.isEmpty) return _currentBalance;
    try {
      final magnitude = _codec.parsePositiveAtomic(raw, unit);
      final delta = _direction == _AdjustmentDirection.add
          ? magnitude
          : -magnitude;
      return '${_codec.formatAtomic(widget.currentBalanceAtomic + delta, unit)} ${unit.simbolo}';
    } on FormatException {
      return '—';
    }
  }

  String get _signedPrefix =>
      _direction == _AdjustmentDirection.add ? '+' : '−';

  Color get _directionColor => _direction == _AdjustmentDirection.add
      ? const Color(0xFF2E7D32)
      : const Color(0xFFC62828);

  String? _validateQuantity(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return widget.quantityRequired
          ? 'Indica la cantidad del movimiento.'
          : null;
    }
    final unit = widget.unit;
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

  String? get _selectedReason {
    if (!_isMovement) {
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
