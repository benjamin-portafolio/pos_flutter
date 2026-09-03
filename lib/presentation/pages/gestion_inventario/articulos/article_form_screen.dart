import 'package:flutter/material.dart';

import '../../../../domain/articulos/nombre_producto.dart';
import '../../../../domain/articulos/nombre_variante.dart';
import '../../../../domain/articulos/costo_estandar.dart';
import '../../../../domain/articulos/precio_venta.dart';
import '../../../../domain/articulos/sale_configuration.dart';
import '../../../../domain/articulos/sale_mode.dart';
import '../../../../domain/categorias/categoria.dart';
import '../../../../domain/inventario/dimension_unidad.dart';
import '../../../../domain/inventario/unidad_inventario.dart';
import '../../../../domain/repositories/recurso_inventario_repository.dart';
import '../recursos/models/inventory_resource_form_result.dart';
import 'models/articulo_form_result.dart';
import 'widgets/advanced_variants_section.dart';
import 'widgets/currency_input_formatter.dart';
import 'widgets/variant_editor_screen.dart';

class ArticleFormScreen extends StatefulWidget {
  const ArticleFormScreen({
    required this.categorias,
    required this.unidadesVenta,
    required this.onSave,
    this.inventoryResourceRepository,
    this.onCreateInventoryResource,
    super.key,
  });

  final List<Categoria> categorias;
  final List<UnidadInventario> unidadesVenta;
  final Future<void> Function(ArticuloFormResult result) onSave;
  final RecursoInventarioRepository? inventoryResourceRepository;
  final Future<void> Function(InventoryResourceFormResult result)?
  onCreateInventoryResource;

  @override
  State<ArticleFormScreen> createState() => _ArticleFormScreenState();
}

class _ArticleFormScreenState extends State<ArticleFormScreen> {
  static const _noCategoryValue = '';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  String? _selectedCategoryId;
  SaleMode _saleMode = SaleMode.unit;
  UnidadInventario? _selectedSaleUnit;
  _ArticleCreationMode _creationMode = _ArticleCreationMode.simple;
  bool _showSaleUnitError = false;
  String? _saveError;
  bool _saving = false;
  bool _canPop = false;
  List<ArticuloFormVarianteResult>? _advancedVariants;
  String? _variantListError;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
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
          title: const Text('AÑADIR ARTÍCULO'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                key: const Key('save_article_button'),
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
        backgroundColor: const Color(0xFFE6E6E6),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FormCard(
                    child: TextFormField(
                      key: const Key('article_name_field'),
                      controller: _nameController,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del artículo *',
                        hintText: 'Introduce el nombre del artículo',
                        border: InputBorder.none,
                        counterText: '',
                        prefixIcon: Icon(Icons.check_circle_outline),
                      ),
                      validator: _validateName,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FormCard(
                    child: DropdownButtonFormField<String>(
                      key: const Key('article_category_field'),
                      initialValue: _selectedCategoryId ?? _noCategoryValue,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: _noCategoryValue,
                          child: Text('Sin categoría'),
                        ),
                        ...widget.categorias.map(
                          (categoria) => DropdownMenuItem<String>(
                            value: categoria.id,
                            child: Text(categoria.nombre),
                          ),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(
                                () => _selectedCategoryId =
                                    value == _noCategoryValue ? null : value,
                              );
                            },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SaleModeCard(
                    saleMode: _saleMode,
                    selectedUnit: _selectedSaleUnit,
                    enabled: !_saving,
                    showUnitError: _showSaleUnitError,
                    onSelectMode: _selectSaleMode,
                    onSelectUnit: _selectSaleUnit,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_ArticleCreationMode>(
                    key: const Key('article_creation_mode_selector'),
                    segments: const [
                      ButtonSegment(
                        value: _ArticleCreationMode.simple,
                        label: Text('Sencillo'),
                      ),
                      ButtonSegment(
                        value: _ArticleCreationMode.advanced,
                        label: Text('Avanzado'),
                      ),
                    ],
                    selected: {_creationMode},
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    onSelectionChanged: _saving
                        ? null
                        : (selection) => _selectCreationMode(selection.single),
                  ),
                  const SizedBox(height: 12),
                  if (_creationMode == _ArticleCreationMode.simple)
                    _FormCard(
                      child: TextFormField(
                        key: const Key('article_price_field'),
                        controller: _priceController,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [CurrencyInputFormatter()],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: _priceLabel,
                          hintText: '0.00',
                          border: InputBorder.none,
                          prefixIcon: const Icon(Icons.attach_money),
                        ),
                        validator: _validatePrice,
                      ),
                    )
                  else
                    AdvancedVariantsSection(
                      variants: _advancedVariants ?? const [],
                      enabled: !_saving,
                      error: _variantListError,
                      onEdit: _editVariant,
                      onAdd: _addVariant,
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
                          key: const Key('article_save_error'),
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

  String? _validateName(String? value) {
    try {
      NombreProducto.fromInput(value ?? '');
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

  String get _priceLabel {
    final unit = _selectedSaleUnit;
    return _saleMode == SaleMode.measured && unit != null
        ? 'Precio de venta por 1 ${unit.simbolo} *'
        : 'Precio de venta *';
  }

  void _selectCreationMode(_ArticleCreationMode mode) {
    if (mode == _creationMode) return;
    FocusScope.of(context).unfocus();
    if (mode == _ArticleCreationMode.simple) {
      final variants = _advancedVariants ?? const [];
      final cannotRepresent =
          variants.length > 1 ||
          variants.any(
            (variant) =>
                NombreVariante.fromInput(variant.nombre).value != null ||
                CostoEstandar.fromInput(variant.costoEstandar) != null ||
                variant.seguimientoExistencias,
          );
      if (cannotRepresent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El modo Sencillo no puede representar las variantes o costos '
              'capturados.',
            ),
          ),
        );
        return;
      }
      if (variants.isNotEmpty) {
        _priceController.text = variants.first.precioVenta;
      }
    }
    setState(() {
      _creationMode = mode;
      _saveError = null;
      _variantListError = null;
      if (mode == _ArticleCreationMode.advanced) {
        final variants = _advancedVariants;
        if (variants == null || variants.isEmpty) {
          _advancedVariants = [
            ArticuloFormVarianteResult(
              nombre: null,
              precioVenta: _priceController.text,
              costoEstandar: null,
            ),
          ];
        } else if (variants.length == 1 &&
            variants.first.nombre == null &&
            variants.first.costoEstandar == null) {
          _advancedVariants = [
            variants.first.copyWith(precioVenta: _priceController.text),
          ];
        }
      }
    });
  }

  Future<void> _editVariant(int index) async {
    if (_saving) return;
    final variants = _advancedVariants;
    if (variants == null || index < 0 || index >= variants.length) return;
    final inventoryUnit = _directInventoryUnit;
    if (inventoryUnit == null) {
      _showInventoryUnitRequired();
      return;
    }
    final result = await Navigator.of(context).push<VariantEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => VariantEditorScreen(
          initialValue: variants[index],
          inventoryUnit: inventoryUnit,
          inventoryUnits: widget.unidadesVenta,
          inventoryResourceRepository: widget.inventoryResourceRepository,
          onCreateInventoryResource: widget.onCreateInventoryResource,
          canDelete: index > 0,
          existingNameKeys: _variantNameKeys(excludingIndex: index),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.deleted) {
        variants.removeAt(index);
      } else {
        variants[index] = result.value!;
      }
      _variantListError = null;
      _saveError = null;
    });
  }

  Future<void> _addVariant() async {
    if (_saving) return;
    final inventoryUnit = _directInventoryUnit;
    if (inventoryUnit == null) {
      _showInventoryUnitRequired();
      return;
    }
    final variants = _advancedVariants;
    if (variants != null &&
        variants.length == 1 &&
        _isEmptyVariantDraft(variants.first)) {
      await _editVariant(0);
      return;
    }
    final result = await Navigator.of(context).push<VariantEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => VariantEditorScreen(
          initialValue: null,
          inventoryUnit: inventoryUnit,
          inventoryUnits: widget.unidadesVenta,
          inventoryResourceRepository: widget.inventoryResourceRepository,
          onCreateInventoryResource: widget.onCreateInventoryResource,
          canDelete: false,
          existingNameKeys: _variantNameKeys(),
        ),
      ),
    );
    if (result?.value == null || !mounted) return;
    setState(() {
      (_advancedVariants ??= []).add(result!.value!);
      _variantListError = null;
      _saveError = null;
    });
  }

  bool _isEmptyVariantDraft(ArticuloFormVarianteResult variant) {
    return (variant.nombre?.trim().isEmpty ?? true) &&
        variant.precioVenta.trim().isEmpty &&
        (variant.costoEstandar?.trim().isEmpty ?? true) &&
        !variant.seguimientoExistencias &&
        !variant.usaReceta &&
        (variant.existenciaInicial?.trim().isEmpty ?? true);
  }

  Set<String> _variantNameKeys({int? excludingIndex}) {
    final keys = <String>{};
    final variants = _advancedVariants ?? const [];
    for (var index = 0; index < variants.length; index++) {
      if (index == excludingIndex) continue;
      final key = NombreVariante.fromInput(variants[index].nombre).nameKey;
      if (key != null) keys.add(key);
    }
    return keys;
  }

  List<UnidadInventario> get _fractionalSaleUnits => widget.unidadesVenta
      .where(
        (unit) =>
            unit.activa &&
            (unit.dimension == DimensionUnidad.mass ||
                unit.dimension == DimensionUnidad.volume),
      )
      .toList(growable: false);

  Future<void> _selectSaleMode() async {
    final selected = await showModalBottomSheet<SaleMode>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SaleModeBottomSheet(selected: _saleMode),
    );
    if (selected == null || selected == _saleMode || !mounted) return;
    if (_hasTrackedVariants) {
      _showTrackedVariantConfigurationWarning();
      return;
    }
    setState(() {
      _saleMode = selected;
      _showSaleUnitError = false;
      if (selected == SaleMode.unit) _selectedSaleUnit = null;
    });
  }

  Future<void> _selectSaleUnit() async {
    final units = _fractionalSaleUnits;
    final selected = await showModalBottomSheet<UnidadInventario>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SaleUnitBottomSheet(
        units: units,
        selectedUnitId: _selectedSaleUnit?.id,
      ),
    );
    if (selected == null || !mounted) return;
    if (_hasTrackedVariants && selected.id != _selectedSaleUnit?.id) {
      _showTrackedVariantConfigurationWarning();
      return;
    }
    setState(() {
      _selectedSaleUnit = selected;
      _showSaleUnitError = false;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final validFields = _formKey.currentState!.validate();
    final validSaleUnit =
        _saleMode == SaleMode.unit || _selectedSaleUnit != null;
    if (!validSaleUnit) setState(() => _showSaleUnitError = true);
    final variants = _creationMode == _ArticleCreationMode.simple
        ? [
            ArticuloFormVarianteResult(
              nombre: null,
              precioVenta: _priceController.text,
              costoEstandar: null,
            ),
          ]
        : List<ArticuloFormVarianteResult>.of(_advancedVariants ?? const []);
    final variantError = _validateVariants(variants);
    if (variantError != null) {
      setState(() => _variantListError = variantError);
    }
    if (!validFields || !validSaleUnit || variantError != null) return;

    final saleConfiguration = _saleMode == SaleMode.unit
        ? const UnitSaleConfiguration()
        : MeasuredSaleConfiguration(
            saleUnitId: _selectedSaleUnit!.id,
            priceReferenceQuantityAtomic: _selectedSaleUnit!.factorAtomico,
          );
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(
        ArticuloFormResult(
          nombre: _nameController.text,
          variantes: List.unmodifiable(variants),
          categoriaId: _selectedCategoryId,
          saleConfiguration: saleConfiguration,
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
        _saveError = 'No se pudo guardar el artículo.';
      });
    }
  }

  String? _validateVariants(List<ArticuloFormVarianteResult> variants) {
    if (variants.isEmpty) return 'Agrega al menos una variante.';
    final nameKeys = <String>{};
    for (final variant in variants) {
      try {
        final name = NombreVariante.fromInput(variant.nombre);
        PrecioVenta.fromInput(variant.precioVenta);
        CostoEstandar.fromInput(variant.costoEstandar);
        if (variant.seguimientoExistencias) {
          final expectedUnit = _directInventoryUnit;
          if (expectedUnit == null ||
              variant.inventoryUnitId != expectedUnit.id) {
            return 'La unidad del seguimiento no coincide con la forma de venta.';
          }
        }
        if (variant.seguimientoExistencias && variant.usaReceta) {
          return 'Una variante no puede usar seguimiento directo y receta simultáneamente.';
        }
        final nameKey = name.nameKey;
        if (nameKey != null && !nameKeys.add(nameKey)) {
          return 'Los nombres de variantes no pueden repetirse.';
        }
      } on ArgumentError catch (error) {
        return error.message?.toString() ?? 'Hay una variante inválida.';
      }
    }
    return null;
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
            key: const Key('discard_article_changes_button'),
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
      _priceController.text.isNotEmpty ||
      _selectedCategoryId != null ||
      _saleMode != SaleMode.unit ||
      _creationMode != _ArticleCreationMode.simple ||
      (_advancedVariants?.any(
            (variant) =>
                variant.nombre != null ||
                variant.precioVenta.isNotEmpty ||
                variant.costoEstandar != null ||
                variant.seguimientoExistencias ||
                variant.usaReceta ||
                variant.existenciaInicial != null,
          ) ??
          false);

  bool get _hasTrackedVariants =>
      _advancedVariants?.any(
        (variant) => variant.seguimientoExistencias || variant.usaReceta,
      ) ??
      false;

  UnidadInventario? get _directInventoryUnit {
    if (_saleMode == SaleMode.measured) return _selectedSaleUnit;
    for (final unit in widget.unidadesVenta) {
      if (unit.activa &&
          unit.dimension == DimensionUnidad.count &&
          unit.factorAtomico == 1) {
        return unit;
      }
    }
    return null;
  }

  void _showInventoryUnitRequired() {
    final message = _saleMode == SaleMode.measured
        ? 'Selecciona primero la unidad de venta.'
        : 'No existe una unidad activa de piezas para controlar existencias.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showTrackedVariantConfigurationWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Retira la configuración de inventario de las variantes antes de '
          'cambiar la forma o unidad de venta.',
        ),
      ),
    );
  }
}

enum _ArticleCreationMode { simple, advanced }

class _FormCard extends StatelessWidget {
  const _FormCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: child,
      ),
    );
  }
}

class _SaleModeCard extends StatelessWidget {
  const _SaleModeCard({
    required this.saleMode,
    required this.selectedUnit,
    required this.enabled,
    required this.showUnitError,
    required this.onSelectMode,
    required this.onSelectUnit,
  });

  final SaleMode saleMode;
  final UnidadInventario? selectedUnit;
  final bool enabled;
  final bool showUnitError;
  final VoidCallback onSelectMode;
  final VoidCallback onSelectUnit;

  @override
  Widget build(BuildContext context) {
    final measured = saleMode == SaleMode.measured;
    final errorColor = Theme.of(context).colorScheme.error;
    return _FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: ListTile(
                    key: const Key('sale_mode_selector'),
                    enabled: enabled,
                    onTap: enabled ? onSelectMode : null,
                    leading: const Icon(Icons.sell_outlined),
                    title: Text(
                      measured ? 'Vender por fracción' : 'Vender por unidad',
                    ),
                    trailing: const Icon(Icons.arrow_drop_down),
                  ),
                ),
                if (measured) ...[
                  const VerticalDivider(width: 1),
                  InkWell(
                    key: const Key('sale_unit_selector'),
                    onTap: enabled ? onSelectUnit : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 88),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              selectedUnit?.simbolo ?? 'Unidad',
                              style: TextStyle(
                                color: showUnitError && selectedUnit == null
                                    ? errorColor
                                    : null,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (measured && showUnitError && selectedUnit == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Selecciona una unidad de venta.',
                key: const Key('sale_unit_error'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: errorColor),
              ),
            ),
        ],
      ),
    );
  }
}

class _SaleModeBottomSheet extends StatelessWidget {
  const _SaleModeBottomSheet({required this.selected});

  final SaleMode selected;

  @override
  Widget build(BuildContext context) {
    return _SelectionBottomSheet<SaleMode>(
      title: 'Forma de venta',
      selected: selected,
      options: const [
        _SelectionOption(
          value: SaleMode.unit,
          key: Key('sale_mode_unit_option'),
          title: 'Vender por unidad',
          description: 'Vender como un conjunto o unidad fija.',
          icon: Icons.shopping_bag_outlined,
        ),
        _SelectionOption(
          value: SaleMode.measured,
          key: Key('sale_mode_measured_option'),
          title: 'Vender por fracción',
          description:
              'Vender a granel utilizando una unidad de medida, por ejemplo kg, g, L o ml.',
          icon: Icons.scale_outlined,
        ),
      ],
    );
  }
}

class _SaleUnitBottomSheet extends StatelessWidget {
  const _SaleUnitBottomSheet({
    required this.units,
    required this.selectedUnitId,
  });

  final List<UnidadInventario> units;
  final String? selectedUnitId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unidad de venta',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (units.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No hay unidades activas de masa o volumen.'),
              )
            else
              ...units.map(
                (unit) => Card(
                  child: ListTile(
                    key: Key('sale_unit_option_${unit.code}'),
                    onTap: () => Navigator.of(context).pop(unit),
                    leading: const Icon(Icons.straighten),
                    title: Text(unit.nombre),
                    subtitle: Text(unit.simbolo),
                    trailing: unit.id == selectedUnitId
                        ? const Icon(Icons.check)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBottomSheet<T> extends StatelessWidget {
  const _SelectionBottomSheet({
    required this.title,
    required this.selected,
    required this.options,
  });

  final String title;
  final T selected;
  final List<_SelectionOption<T>> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...options.map(
              (option) => Card(
                child: ListTile(
                  key: option.key,
                  onTap: () => Navigator.of(context).pop(option.value),
                  leading: Icon(option.icon),
                  title: Text(option.title),
                  subtitle: Text(option.description),
                  trailing: option.value == selected
                      ? const Icon(Icons.check)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionOption<T> {
  const _SelectionOption({
    required this.value,
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final T value;
  final Key key;
  final String title;
  final String description;
  final IconData icon;
}
