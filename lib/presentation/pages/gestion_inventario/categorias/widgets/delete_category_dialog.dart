import 'package:flutter/material.dart';

class DeleteCategoryDialog extends StatelessWidget {
  const DeleteCategoryDialog.confirm({
    required this.categoryName,
    required this.onDelete,
    required this.deleting,
    super.key,
  }) : linkedCount = 0,
       checking = false;

  const DeleteCategoryDialog.blocked({
    required this.categoryName,
    required this.linkedCount,
    super.key,
  }) : onDelete = null,
       deleting = false,
       checking = false;

  const DeleteCategoryDialog.checking({required this.categoryName, super.key})
    : linkedCount = 0,
      onDelete = null,
      deleting = false,
      checking = true;

  final String categoryName;
  final int linkedCount;
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

    final blocked = linkedCount > 0;
    final noun = linkedCount == 1
        ? 'artículo vinculado'
        : 'artículos vinculados';
    return PopScope(
      canPop: !deleting,
      child: AlertDialog(
        title: blocked ? null : const Text('Eliminar categoría'),
        content: Text(
          blocked
              ? 'La categoría “$categoryName” tiene $linkedCount $noun. '
                    'Esta categoría no puede eliminarse hasta resolver sus '
                    'artículos vinculados.'
              : '¿Quieres eliminar la categoría “$categoryName”? Esta acción '
                    'no se puede deshacer.',
        ),
        actions: blocked
            ? [
                TextButton(
                  key: const Key('close_delete_category_dialog_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ]
            : [
                TextButton(
                  key: const Key('cancel_delete_category_button'),
                  onPressed: deleting
                      ? null
                      : () => Navigator.of(context).pop(),
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
