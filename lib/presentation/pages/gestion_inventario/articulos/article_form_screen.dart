import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/articulos/nombre_producto.dart';
import '../../../../domain/articulos/precio_venta.dart';
import '../../../../domain/categorias/categoria.dart';
import 'models/articulo_form_result.dart';

class ArticleFormScreen extends StatefulWidget {
  const ArticleFormScreen({
    required this.categorias,
    required this.onSave,
    super.key,
  });

  final List<Categoria> categorias;
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
                  const _FormCard(
                    child: ListTile(
                      leading: Icon(Icons.sell_outlined),
                      title: Text('Vender por unidad'),
                      subtitle: Text(
                        'Artículo sencillo sin control de inventario',
                      ),
                    ),
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
                      decoration: const InputDecoration(
                        labelText: 'Precio de venta *',
                        hintText: '0.00',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.attach_money),
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

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

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
      _selectedCategoryId != null;
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
