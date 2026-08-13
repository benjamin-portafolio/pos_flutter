import 'package:flutter/material.dart';

import '../models/delete_category_product_action.dart';

class DeleteCategoryOptionsDialog extends StatelessWidget {
  const DeleteCategoryOptionsDialog({
    required this.categoryName,
    required this.linkedCount,
    super.key,
  });

  final String categoryName;
  final int linkedCount;

  @override
  Widget build(BuildContext context) {
    final noun = linkedCount == 1
        ? 'artículo vinculado'
        : 'artículos vinculados';
    return AlertDialog(
      key: const Key('delete_category_options_dialog'),
      content: Text(
        'La categoría “$categoryName” tiene $linkedCount $noun. Antes de '
        'eliminarla, elige qué hacer con sus artículos.',
      ),
      actions: [
        TextButton(
          key: const Key('cancel_delete_category_with_products_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: const Key('uncategorize_category_products_option'),
          onPressed: () => Navigator.of(
            context,
          ).pop(DeleteCategoryProductAction.uncategorize),
          child: const Text('Dejar sin categoría'),
        ),
        TextButton(
          key: const Key('move_category_products_option'),
          onPressed: () =>
              Navigator.of(context).pop(DeleteCategoryProductAction.move),
          child: const Text('Mover a otra categoría'),
        ),
      ],
    );
  }
}
