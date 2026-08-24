import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/articulos/nombre_producto.dart';
import '../../../../domain/articulos/precio_venta.dart';
import '../../../../domain/articulos/sale_configuration.dart';
import '../../../../domain/articulos/sale_mode.dart';
import '../../../../domain/categorias/categoria.dart';
import '../../../../domain/inventario/dimension_unidad.dart';
import '../../../../domain/inventario/unidad_inventario.dart';
import 'models/articulo_form_result.dart';

class ArticleFormScreen extends StatefulWidget {
  const ArticleFormScreen({
    required this.categorias,
    required this.unidadesVenta,
    required this.onSave,
    super.key,
  });

  final List<Categoria> categorias;
  final List<UnidadInventario> unidadesVenta;
  final Future<void> Function(ArticuloFormResult result) onSave;

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
  bool _showSaleUnitError = false;
  String? _saveError;
  bool _saving = false;
  bool _canPop = false;

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
                  _FormCard(
                    child: TextFormField(
                      key: const Key('article_price_field'),
                      controller: _priceController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [_CurrencyInputFormatter()],
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
    if (!validFields || !validSaleUnit) return;

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
          precioVenta: _priceController.text,
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
      _saleMode != SaleMode.unit;
}

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

class _CurrencyInputFormatter extends TextInputFormatter {
  const _CurrencyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final accepted = RegExp(r'^\d*(?:[.,]\d{0,2})?$');
    return accepted.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
