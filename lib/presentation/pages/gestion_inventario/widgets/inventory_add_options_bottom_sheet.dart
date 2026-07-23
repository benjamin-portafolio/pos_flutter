import 'package:flutter/material.dart';

class InventoryAddOptionsBottomSheet extends StatelessWidget {
  const InventoryAddOptionsBottomSheet({
    required this.onAddCategory,
    super.key,
  });

  final VoidCallback onAddCategory;

  static Future<void> show({
    required BuildContext context,
    required VoidCallback onAddCategory,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) =>
          InventoryAddOptionsBottomSheet(onAddCategory: onAddCategory),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _InventoryAddOption(
                    key: Key('add_article_option'),
                    label: 'Añadir artículo',
                  ),
                ),
                Expanded(
                  child: _InventoryAddOption(
                    key: const Key('add_category_option'),
                    label: 'Añadir categoría',
                    onTap: () {
                      Navigator.of(context).pop();
                      onAddCategory();
                    },
                  ),
                ),
              ],
            ),
            const Row(
              children: [
                Expanded(
                  child: _InventoryAddOption(
                    key: Key('add_modifier_option'),
                    label: 'Añadir modificador',
                  ),
                ),
                Expanded(
                  child: _InventoryAddOption(
                    key: Key('add_ingredient_option'),
                    label: 'Agregar ingrediente',
                  ),
                ),
              ],
            ),
            const SizedBox(
              width: double.infinity,
              child: _InventoryAddOption(
                key: Key('bulk_edit_option'),
                label: 'Edición masiva',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryAddOption extends StatelessWidget {
  const _InventoryAddOption({required this.label, this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: const RoundedRectangleBorder(),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 76,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
