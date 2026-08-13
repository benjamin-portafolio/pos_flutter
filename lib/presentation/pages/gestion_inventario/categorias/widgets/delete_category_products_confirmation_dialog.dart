import 'package:flutter/material.dart';

import '../models/delete_category_product_action.dart';

class DeleteCategoryProductsConfirmationDialog extends StatelessWidget {
  const DeleteCategoryProductsConfirmationDialog({
    required this.categoryName,
    required this.linkedCount,
    required this.action,
    required this.deleting,
    required this.onConfirm,
    this.destinationName,
    super.key,
  });

  final String categoryName;
  final int linkedCount;
  final DeleteCategoryProductAction action;
  final String? destinationName;
  final bool deleting;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final content = linkedCount == 1
        ? switch (action) {
            DeleteCategoryProductAction.move =>
              'Se moverá 1 artículo de “$categoryName” a “$destinationName” '
                  'y se eliminará la categoría “$categoryName”.',
            DeleteCategoryProductAction.uncategorize =>
              'El artículo vinculado quedará sin categoría y se eliminará '
                  'la categoría “$categoryName”.',
          }
        : switch (action) {
            DeleteCategoryProductAction.move =>
              'Se moverán $linkedCount artículos de “$categoryName” a '
                  '“$destinationName” y se eliminará la categoría '
                  '“$categoryName”.',
            DeleteCategoryProductAction.uncategorize =>
              'Los $linkedCount artículos vinculados quedarán sin categoría '
                  'y se eliminará la categoría “$categoryName”.',
          };
    final confirmText = switch (action) {
      DeleteCategoryProductAction.move => 'Mover y eliminar',
      DeleteCategoryProductAction.uncategorize =>
        'Dejar sin categoría y eliminar',
    };
    final key = switch (action) {
      DeleteCategoryProductAction.move => const Key(
        'confirm_move_and_delete_category_button',
      ),
      DeleteCategoryProductAction.uncategorize => const Key(
        'confirm_uncategorize_and_delete_category_button',
      ),
    };

    return PopScope(
      canPop: !deleting,
      child: AlertDialog(
        key: const Key('delete_category_products_confirmation_dialog'),
        content: Text(content),
        actions: [
          TextButton(
            key: const Key('cancel_category_product_resolution_button'),
            onPressed: deleting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: key,
            onPressed: deleting ? null : onConfirm,
            child: deleting
                ? const SizedBox(
                    key: Key('delete_category_products_busy_indicator'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(confirmText),
          ),
        ],
      ),
    );
  }
}
