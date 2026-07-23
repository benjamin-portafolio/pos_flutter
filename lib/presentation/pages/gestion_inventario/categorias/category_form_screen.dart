import 'package:flutter/material.dart';

import '../../../../domain/categorias/color_categoria.dart';
import 'category_color_palette.dart';
import 'models/categoria_form_result.dart';
import 'widgets/category_color_picker_dialog.dart';

class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({this.initialValue, super.key});

  final CategoriaFormResult? initialValue;

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late ColorCategoria _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue?.nombre ?? '',
    );
    _selectedColor = widget.initialValue?.color ?? ColorCategoria.neutral;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Cancelar',
        ),
        title: const Text('CATEGORÍA'),
        actions: [
          TextButton.icon(
            key: const Key('save_category_button'),
            onPressed: _submit,
            style: TextButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('GUARDAR'),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFE6E6E6),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _ColorPreview(
                  color: CategoryColorPalette.resolve(_selectedColor),
                  onEdit: _selectColor,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  key: const Key('category_name_field'),
                  controller: _nameController,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la categoría',
                    hintText: 'Introduce el nombre de la categoría',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'El nombre de la categoría es obligatorio.'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectColor() async {
    final color = await CategoryColorPickerDialog.show(
      context: context,
      initialColor: _selectedColor,
    );
    if (color == null || !mounted) return;
    setState(() => _selectedColor = color);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CategoriaFormResult(nombre: _nameController.text, color: _selectedColor),
    );
  }
}

class _ColorPreview extends StatelessWidget {
  const _ColorPreview({required this.color, required this.onEdit});

  final Color color;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.palette_outlined,
              color: Colors.white,
              size: 72,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              shape: const CircleBorder(),
              elevation: 4,
              child: IconButton(
                key: const Key('edit_category_color_button'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
                tooltip: 'Elegir color',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
