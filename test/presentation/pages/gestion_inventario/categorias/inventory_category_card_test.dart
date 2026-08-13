import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/widgets/inventory_category_card.dart';

void main() {
  testWidgets('papelera elimina sin disparar edición', (tester) async {
    var edits = 0;
    var deletes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoryCard(
            name: 'Bebidas',
            color: Colors.cyan,
            onTap: () => edits++,
            onMoveUp: null,
            onMoveDown: null,
            onDeleteCategory: () => deletes++,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('delete_category_button')));
    expect(deletes, 1);
    expect(edits, 0);

    await tester.tap(find.text('Bebidas'));
    expect(edits, 1);
  });
}
