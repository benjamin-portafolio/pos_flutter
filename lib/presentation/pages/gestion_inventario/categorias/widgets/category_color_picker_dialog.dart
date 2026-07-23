import 'package:flutter/material.dart';

import '../../../../../domain/categorias/color_categoria.dart';
import '../category_color_palette.dart';

class CategoryColorPickerDialog extends StatefulWidget {
  const CategoryColorPickerDialog({required this.initialColor, super.key});

  final ColorCategoria initialColor;

  static Future<ColorCategoria?> show({
    required BuildContext context,
    required ColorCategoria initialColor,
  }) {
    return showDialog<ColorCategoria>(
      context: context,
      builder: (_) => CategoryColorPickerDialog(initialColor: initialColor),
    );
  }

  @override
  State<CategoryColorPickerDialog> createState() =>
      _CategoryColorPickerDialogState();
}

class _CategoryColorPickerDialogState extends State<CategoryColorPickerDialog> {
  late ColorCategoria _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Elige un color'),
      content: SizedBox(
        width: 320,
        child: GridView.builder(
          shrinkWrap: true,
          itemCount: CategoryColorPalette.selectableColors.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final color = CategoryColorPalette.selectableColors[index];
            final selected = color == _selectedColor;
            return InkWell(
              key: Key('category_color_${color.key}'),
              onTap: () => setState(() => _selectedColor = color),
              borderRadius: BorderRadius.circular(4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: CategoryColorPalette.resolve(color),
                  borderRadius: BorderRadius.circular(4),
                  border: selected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      offset: Offset(0, 2),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        TextButton(
          onPressed: _selectedColor == ColorCategoria.neutral
              ? null
              : () => Navigator.of(context).pop(_selectedColor),
          child: const Text('ACEPTAR'),
        ),
      ],
    );
  }
}
