import 'package:flutter/material.dart';

class DeleteCategoryDialog extends StatelessWidget {
  const DeleteCategoryDialog.confirm({
    required this.categoryName,
    required this.onDelete,
    required this.deleting,
    super.key,
  }) : checking = false;

  const DeleteCategoryDialog.checking({required this.categoryName, super.key})
    : onDelete = null,
      deleting = false,
      checking = true;

  final String categoryName;
  final VoidCallback? onDelete;
  final bool deleting;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Comprobando artículos vinculados…')),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !deleting,
      child: AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(
          '¿Quieres eliminar la categoría “$categoryName”? Esta acción '
          'no se puede deshacer.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel_delete_category_button'),
            onPressed: deleting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_delete_category_button'),
            onPressed: deleting ? null : onDelete,
            child: deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
