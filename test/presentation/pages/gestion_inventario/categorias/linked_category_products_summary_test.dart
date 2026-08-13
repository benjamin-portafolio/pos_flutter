import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/articulo_vinculado_categoria.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/models/linked_category_products_summary.dart';

void main() {
  test('cuenta activos e inactivos y conserva el conjunto exacto por ID', () {
    final summary = LinkedCategoryProductsSummary(const [
      ArticuloVinculadoCategoria(productoId: 'product-2', activo: false),
      ArticuloVinculadoCategoria(productoId: 'product-1', activo: true),
      ArticuloVinculadoCategoria(productoId: 'product-3', activo: false),
    ]);

    expect(summary.total, 3);
    expect(summary.activos, 1);
    expect(summary.inactivos, 2);
    expect(summary.productIds, ['product-1', 'product-2', 'product-3']);
  });
}
