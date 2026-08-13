import 'package:flutter/material.dart';

class InventoryCategoryCard extends StatelessWidget {
  const InventoryCategoryCard({
    required this.name,
    required this.color,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDeleteCategory,
    super.key,
  });

  final String name;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDeleteCategory;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 92,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Semantics(
                  label: 'Eliminar categoría $name',
                  button: true,
                  child: IconButton(
                    key: const Key('delete_category_button'),
                    onPressed: onDeleteCategory,
                    color: const Color(0xFFFF493D),
                    tooltip: 'Eliminar categoría',
                    icon: const Icon(Icons.delete_forever),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  key: const Key('move_category_down_button'),
                  onPressed: onMoveDown,
                  color: primaryColor,
                  disabledColor: primaryColor.withValues(alpha: 0.35),
                  tooltip: 'Bajar categoría',
                  icon: const Icon(Icons.arrow_drop_down, size: 32),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('move_category_up_button'),
                  onPressed: onMoveUp,
                  color: primaryColor,
                  disabledColor: primaryColor.withValues(alpha: 0.35),
                  tooltip: 'Subir categoría',
                  icon: const Icon(Icons.arrow_drop_up, size: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
