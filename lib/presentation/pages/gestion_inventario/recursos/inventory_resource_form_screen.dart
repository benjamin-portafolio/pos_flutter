import 'package:flutter/material.dart';

import '../../../../domain/inventario/nombre_recurso_inventario.dart';
import '../../../../application/sync/projections/inventory_projection_store.dart';
import '../../../../domain/inventario/recurso_inventario_listado.dart';
import '../../../../domain/inventario/unidad_inventario.dart';
import 'models/inventory_resource_form_result.dart';
import 'widgets/inventory_form_card.dart';
import 'widgets/inventory_movement_section.dart';
import 'widgets/inventory_unit_picker.dart';

class InventoryResourceFormScreen extends StatefulWidget {
  const InventoryResourceFormScreen({
    required this.units,
    required this.onSave,
    super.key,
  }) : resource = null,
       onDelete = null;

  const InventoryResourceFormScreen.edit({
    required this.resource,
    required this.onSave,
    this.onDelete,
    super.key,
  }) : units = const [];

  final List<UnidadInventario> units;
  final Future<void> Function(InventoryResourceFormResult result) onSave;
  final RecursoInventarioListado? resource;
  final Future<void> Function()? onDelete;

  @override
  State<InventoryResourceFormScreen> createState() =>
      _InventoryResourceFormScreenState();
}

class _InventoryResourceFormScreenState
    extends State<InventoryResourceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _errorKey = GlobalKey();
  final _movementKey = GlobalKey<InventoryMovementSectionState>();
  final _nameController = TextEditingController();
  UnidadInventario? _selectedUnit;
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
                  InventoryFormCard(
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
                  InventoryMovementSection(
                    key: _movementKey,
                    mode: _editing
                        ? InventoryMovementSectionMode.movement
                        : InventoryMovementSectionMode.initialBalance,
                    unit: _selectedUnit,
                    currentBalanceAtomic:
                        widget.resource?.existenciaAtomica ?? 0,
                    busy: _saving,
                  ),
                  if (_editing && widget.onDelete != null) ...[
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      key: const Key('delete_inventory_resource_button'),
                      onPressed: _saving ? null : _delete,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('ELIMINAR RECURSO'),
                    ),
                  ],
                  if (_saveError != null) ...[
                    const SizedBox(height: 16),
                    Material(
                      key: _errorKey,
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
    return InventoryFormCard(
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
                      setState(() => _selectedUnit = selected);
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

  String? _validateName(String? value) {
    try {
      NombreRecursoInventario.fromInput(value ?? '');
      return null;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? 'Nombre inválido.';
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final validFields = _formKey.currentState!.validate();
    final validMovement = _movementKey.currentState?.validate() ?? true;
    if (!validFields || !validMovement) return;
    final draft = _movementKey.currentState?.readDraft();

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(
        InventoryResourceFormResult(
          nombre: _nameController.text,
          unidad: _selectedUnit!,
          quantityDeltaAtomic: draft?.quantityDeltaAtomic,
          movementReason: draft?.reason,
          movementType: draft?.movementType,
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

  Future<void> _delete() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar recurso'),
        content: Text(
          '¿Eliminar "${widget.resource!.nombre}" del inventario? Se conservará su historial.'
          '${_hasChanges ? " Los cambios de nombre o existencias sin guardar se descartarán." : ""}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onDelete!();
      if (!mounted) return;
      setState(() => _canPop = true);
      await Future<void>.delayed(Duration.zero);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error is InventoryProjectionConflict
            ? error.message
            : 'No se pudo eliminar el recurso de inventario.';
      });
      await WidgetsBinding.instance.endOfFrame;
      final errorContext = _errorKey.currentContext;
      if (errorContext != null && errorContext.mounted) {
        await Scrollable.ensureVisible(
          errorContext,
          alignment: 1,
          duration: const Duration(milliseconds: 200),
        );
      }
    }
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
    final movementChanges =
        _movementKey.currentState?.hasPendingChanges ?? false;
    if (resource == null) {
      return _nameController.text.isNotEmpty ||
          _selectedUnit != null ||
          movementChanges;
    }
    return _nameController.text != resource.nombre || movementChanges;
  }
}
