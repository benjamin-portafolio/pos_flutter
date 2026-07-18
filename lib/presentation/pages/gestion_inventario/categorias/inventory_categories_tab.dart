import 'package:flutter/material.dart';

import 'widgets/inventory_category_card.dart';

class InventoryCategoriesTab extends StatelessWidget {
  const InventoryCategoriesTab({super.key});

  static const _mockCategories = <({String name, Color color})>[
    (name: 'Bebidas', color: Color(0xFF12B8C7)),
    (name: 'Pescados Y Mariscos', color: Color(0xFF4F4F4F)),
    (name: 'Cerveza', color: Color(0xFFFF493D)),
    (name: 'Festival', color: Color(0xFF4F4F4F)),
    (name: 'Souvenirs', color: Color(0xFF4F4F4F)),
    (name: 'Maquila', color: Color(0xFF4F4F4F)),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('inventory_categories_tab_view'),
      color: const Color(0xFFE6E6E6),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: _mockCategories.length,
        itemBuilder: (context, index) {
          final category = _mockCategories[index];
          return InventoryCategoryCard(
            name: category.name,
            color: category.color,
          );
        },
      ),
    );
  }
}
