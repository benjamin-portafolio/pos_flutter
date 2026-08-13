import 'package:flutter/material.dart';

import '../../../../../domain/categorias/categoria.dart';

class CategoryDestinationPickerDialog extends StatefulWidget {
  const CategoryDestinationPickerDialog({required this.categories, super.key});

  final List<Categoria> categories;

  @override
  State<CategoryDestinationPickerDialog> createState() =>
      _CategoryDestinationPickerDialogState();
}

class _CategoryDestinationPickerDialogState
    extends State<CategoryDestinationPickerDialog> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    return AlertDialog(
      key: const Key('category_destination_picker_dialog'),
      title: const Text('Mover a otra categoría'),
      content: categories.isEmpty
          ? const Text('No hay otra categoría disponible.')
          : SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final category in categories)
                    ListTile(
                      key: Key('destination_category_option_${category.id}'),
                      title: Text(category.nombre),
                      selected: _selectedId == category.id,
                      leading: Icon(
                        _selectedId == category.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      onTap: () => setState(() => _selectedId = category.id),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          key: const Key('back_from_destination_picker_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Regresar'),
        ),
        if (categories.isNotEmpty)
          FilledButton(
            key: const Key('confirm_destination_category_button'),
            onPressed: _selectedId == null
                ? null
                : () => Navigator.of(context).pop(
                    categories.firstWhere(
                      (category) => category.id == _selectedId,
                    ),
                  ),
            child: const Text('Continuar'),
          ),
      ],
    );
  }
}
