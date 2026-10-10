import 'package:flutter/material.dart';

import '../../../../../application/config/app_config.dart';
import '../../../../../application/config/app_config_controller.dart';
import '../../../../../domain/articulos/proveedor_variante.dart';
import '../../../../../domain/proveedores/proveedor.dart';
import '../../../../../domain/repositories/proveedor_repository.dart';
import '../models/proveedor_precio_form.dart';
import '../models/proveedor_precio_input.dart';
import '../models/proveedor_precios_form_result.dart';
import 'proveedor_precio_card.dart';

/// Editor local de borrador. Solo devuelve el conjunto completo al guardarlo.
class VariantSuppliersEditorScreen extends StatefulWidget {
  const VariantSuppliersEditorScreen({
    required this.repository,
    required this.config,
    required this.initialValue,
    required this.presentationLabel,
    required this.priceBasis,
    super.key,
  });

  final ProveedorRepository repository;
  final AppConfigController config;
  final List<ProveedorVariante> initialValue;
  final String presentationLabel;
  final String priceBasis;

  @override
  State<VariantSuppliersEditorScreen> createState() =>
      _VariantSuppliersEditorScreenState();
}

class _VariantSuppliersEditorScreenState
    extends State<VariantSuppliersEditorScreen> {
  late Stream<List<Proveedor>> _catalog;
  final _selected = <String, ProveedorPrecioForm>{};
  final _deselected = <String, ProveedorPrecioForm>{};
  final _controllers = <String, TextEditingController>{};
  final _priceErrors = <String, String>{};
  final _dateErrors = <String, String>{};
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _catalog = widget.repository.watchProveedores();
    for (final relation in ProveedorVariante.canonical(widget.initialValue)!) {
      final form = ProveedorPrecioForm.fromRelacion(relation);
      _selected[relation.proveedorId] = form;
      _controllers[relation.proveedorId] = TextEditingController(
        text: form.precio,
      );
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
  Widget build(BuildContext context) => StreamBuilder<AppConfig>(
    stream: widget.config.changes,
    initialData: widget.config.config,
    builder: (context, mode) {
      final available = mode.hasData;
      return Scaffold(
        key: const Key('variant_suppliers_editor_screen'),
        appBar: AppBar(
          leading: IconButton(
            key: const Key('close_variant_suppliers_button'),
            tooltip: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          title: const Text('PROVEEDORES'),
        ),
        body: SafeArea(
          child: available
              ? StreamBuilder<List<Proveedor>>(
                  stream: _catalog,
                  builder: _buildCatalog,
                )
              : const Center(
                  key: Key('variant_suppliers_unavailable'),
                  child: Text(
                    'No se pudo cargar la configuración.',
                  ),
                ),
        ),
      );
    },
  );

  Widget _buildCatalog(
    BuildContext context,
    AsyncSnapshot<List<Proveedor>> snapshot,
  ) {
    if (snapshot.hasError) {
      return Center(
        key: const Key('variant_suppliers_error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No se pudieron cargar los proveedores.'),
            TextButton(
              key: const Key('retry_variant_suppliers_button'),
              onPressed: () => setState(() {
                _catalog = widget.repository.watchProveedores();
              }),
              child: const Text('REINTENTAR'),
            ),
          ],
        ),
      );
    }
    if (!snapshot.hasData) {
      return const Center(
        key: Key('variant_suppliers_loading'),
        child: CircularProgressIndicator(),
      );
    }
    final catalog = {for (final p in snapshot.data!) p.id: p};
    // Una relación cuyo catálogo no está disponible sigue visible y solo se
    // retira explícitamente. Una recarga nunca limpia el borrador.
    final ids = {...catalog.keys, ..._selected.keys};
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.presentationLabel,
                key: const Key('supplier_presentation_label'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(widget.priceBasis, key: const Key('supplier_price_basis')),
              const SizedBox(height: 8),
              const Text(
                'Selecciona proveedores y captura sus precios. Para crear uno, usa la pestaña PROVEEDORES.',
              ),
              if (_saveError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _saveError!,
                  key: const Key('variant_suppliers_save_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              if (catalog.isEmpty)
                const Padding(
                  key: Key('variant_suppliers_empty'),
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Aún no hay proveedores en el catálogo.'),
                ),
              for (final id in ids)
                ProveedorPrecioCard(
                  key: Key('variant_supplier_card_$id'),
                  id: id,
                  nombre:
                      catalog[id]?.nombre ?? 'Proveedor $id (no disponible)',
                  form: _selected[id],
                  controller: _controllers.putIfAbsent(
                    id,
                    TextEditingController.new,
                  ),
                  priceError: _priceErrors[id],
                  dateError: _dateErrors[id],
                  onSelected: (selected) => _select(id, selected),
                  onPriceChanged: (price) => setState(() {
                    _selected[id] = _selected[id]!.copyWith(precio: price);
                    _priceErrors.remove(id);
                    _dateErrors.remove(id);
                    _saveError = null;
                  }),
                  onDate: () => _pickDate(id),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('save_variant_suppliers_button'),
                onPressed: () => _save(catalog),
                icon: const Icon(Icons.check),
                label: const Text('GUARDAR'),
              ),
              const SizedBox(height: 8),
              const Text('Estos cambios se aplicarán al guardar el artículo.'),
            ],
          ),
        ),
      ),
    );
  }

  void _select(String id, bool selected) {
    setState(() {
      if (selected) {
        final original = widget.initialValue
            .where((r) => r.proveedorId == id)
            .firstOrNull;
        _selected[id] =
            _deselected.remove(id) ??
            (original == null
                ? ProveedorPrecioForm(
                    proveedorId: id,
                    precio: _controllers[id]!.text,
                    fecha: DateTime.now(),
                  )
                : ProveedorPrecioForm.fromRelacion(
                    original,
                  ).copyWith(precio: _controllers[id]!.text));
      } else {
        final form = _selected.remove(id);
        if (form != null) _deselected[id] = form;
      }
      _priceErrors.remove(id);
      _dateErrors.remove(id);
      _saveError = null;
    });
  }

  Future<void> _pickDate(String id) async {
    final form = _selected[id];
    if (form == null || form.conservaFecha) return;
    final first = DateTime(1970);
    final last = DateTime(9999, 12, 31);
    final current = form.fecha ?? DateTime.now();
    final initial = current.isBefore(first)
        ? first
        : current.isAfter(last)
        ? last
        : current;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Fecha del precio informado',
    );
    if (date == null || !mounted || !_selected.containsKey(id)) {
      return;
    }
    setState(() {
      _selected[id] = _selected[id]!.copyWith(fecha: date);
      _dateErrors.remove(id);
      _saveError = null;
    });
  }

  void _save(Map<String, Proveedor> catalog) {
    final relations = <ProveedorVariante>[];
    _priceErrors.clear();
    _dateErrors.clear();
    for (final form in _selected.values) {
      if (!catalog.containsKey(form.proveedorId)) {
        _priceErrors[form.proveedorId] =
            'Proveedor no disponible. Reintenta o retira la selección.';
        continue;
      }
      try {
        ProveedorPrecioInput.parse(form.precio);
      } on FormatException catch (error) {
        _priceErrors[form.proveedorId] = error.message;
        continue;
      }
      try {
        relations.add(form.toRelacion());
      } on FormatException catch (error) {
        _dateErrors[form.proveedorId] = error.message;
      }
    }
    if (_priceErrors.isNotEmpty || _dateErrors.isNotEmpty) {
      setState(
        () => _saveError = 'Corrige los campos marcados antes de guardar.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(ProveedorPreciosFormResult(relations));
  }
}
