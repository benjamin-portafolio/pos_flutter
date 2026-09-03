import 'package:flutter/material.dart';

import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../../domain/inventario/recurso_inventario_listado.dart';
import '../../../../../domain/inventario/unidad_inventario.dart';
import '../../../../../domain/repositories/recurso_inventario_repository.dart';
import '../../recursos/inventory_resource_form_screen.dart';
import '../../recursos/inventory_resources_tab.dart';
import '../../recursos/models/inventory_resource_form_result.dart';
import '../../recursos/widgets/inventory_quantity_input_formatter.dart';
import '../models/recipe_component_form_result.dart';

class RecipeEditorScreen extends StatefulWidget {
  const RecipeEditorScreen({
    required this.repository,
    required this.units,
    required this.initialValue,
    required this.onCreateInventoryResource,
    super.key,
  });

  final RecursoInventarioRepository repository;
  final List<UnidadInventario> units;
  final List<RecipeComponentFormResult> initialValue;
  final Future<void> Function(InventoryResourceFormResult result)
  onCreateInventoryResource;

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  static const _codec = InventoryQuantityCodec();

  final _controllers = <String, TextEditingController>{};
  final _resources = <String, RecursoInventarioListado>{};
  final _errors = <String, String?>{};
  String? _saveError;
  bool _creatingResource = false;

  @override
  void initState() {
    super.initState();
    for (final component in widget.initialValue) {
      _resources[component.resource.id] = component.resource;
      _createController(component.resource.id, initialText: component.quantity);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('recipe_editor_screen'),
      appBar: AppBar(
        leading: IconButton(
          key: const Key('close_recipe_editor_button'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Cerrar',
        ),
        title: const Text('COMPONENTES DE LA RECETA'),
        actions: [
          TextButton.icon(
            key: const Key('save_recipe_button'),
            onPressed: _save,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('GUARDAR'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_saveError != null)
            MaterialBanner(
              key: const Key('recipe_save_error'),
              content: Text(_saveError!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _saveError = null),
                  child: const Text('ENTENDIDO'),
                ),
              ],
            ),
          Expanded(
            child: InventoryResourcesTab(
              repository: widget.repository,
              title: 'Elige recursos y asigna cantidades',
              itemBuilder: _buildResource,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            key: const Key('add_recipe_inventory_resource_button'),
            onPressed: _creatingResource ? null : _openInventoryResourceForm,
            icon: _creatingResource
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: const Text('AGREGAR RECURSO DE INVENTARIO'),
          ),
        ),
      ),
    );
  }

  Widget _buildResource(
    BuildContext context,
    RecursoInventarioListado resource,
  ) {
    _resources[resource.id] = resource;
    final controller =
        _controllers[resource.id] ?? _createController(resource.id);
    final unit = resource.unidadPredeterminada;
    final balance = _codec.formatAtomic(resource.existenciaAtomica, unit);
    return Card(
      key: Key('recipe_resource_${resource.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.nombre,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Disponible: $balance ${unit.simbolo}'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 150,
              child: TextField(
                key: Key('recipe_quantity_${resource.id}'),
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  InventoryQuantityInputFormatter(unit.maximosDecimales),
                ],
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  suffixText: unit.simbolo,
                  errorText: _errors[resource.id],
                  errorMaxLines: 3,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextEditingController _createController(
    String resourceId, {
    String initialText = '',
  }) {
    final controller = TextEditingController(text: initialText);
    controller.addListener(() {
      if (!mounted) return;
      if (_errors[resourceId] != null || _saveError != null) {
        setState(() {
          _errors[resourceId] = null;
          _saveError = null;
        });
      }
    });
    _controllers[resourceId] = controller;
    return controller;
  }

  void _save() {
    final components = <RecipeComponentFormResult>[];
    final errors = <String, String?>{};
    for (final entry in _controllers.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) continue;
      final resource = _resources[entry.key];
      if (resource == null) continue;
      try {
        _codec.parsePositiveAtomic(raw, resource.unidadPredeterminada);
        components.add(
          RecipeComponentFormResult(
            resource: resource,
            quantity: raw.replaceAll(',', '.'),
          ),
        );
      } on FormatException catch (error) {
        errors[entry.key] = error.message;
      }
    }
    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
        _saveError = 'Corrige las cantidades marcadas antes de guardar.';
      });
      return;
    }
    if (components.isEmpty) {
      setState(() {
        _saveError =
            'Asigna una cantidad positiva al menos a un recurso de inventario.';
      });
      return;
    }
    components.sort(
      (left, right) => left.resource.id.compareTo(right.resource.id),
    );
    Navigator.of(
      context,
    ).pop(List<RecipeComponentFormResult>.unmodifiable(components));
  }

  Future<void> _openInventoryResourceForm() async {
    setState(() => _creatingResource = true);
    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => InventoryResourceFormScreen(
            units: widget.units,
            onSave: widget.onCreateInventoryResource,
          ),
        ),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Recurso guardado. Asígnale una cantidad para incluirlo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingResource = false);
    }
  }
}
