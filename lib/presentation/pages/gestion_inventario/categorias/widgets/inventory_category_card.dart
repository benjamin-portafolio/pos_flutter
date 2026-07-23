import 'package:flutter/material.dart';

class InventoryCategoryCard extends StatelessWidget {
  const InventoryCategoryCard({
    required this.name,
    required this.color,
    required this.onTap,
    super.key,
  });

  final String name;
  final Color color;
  final VoidCallback onTap;

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
                const Icon(Icons.delete_forever, color: Color(0xFFFF493D)),
                const SizedBox(width: 22),
                Icon(Icons.arrow_drop_down, color: primaryColor, size: 32),
                const SizedBox(width: 16),
                Icon(Icons.arrow_drop_up, color: primaryColor, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
