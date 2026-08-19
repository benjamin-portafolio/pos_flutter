import 'package:drift/drift.dart';

import 'common_fields.dart';
import 'inventory_items.dart';
import 'products.dart';

/// Proyeccion local de la unica presentacion vendible creada por el alta
/// sencilla. Las variantes multiples y sus identificadores quedan fuera de
/// este alcance.
@DataClassName('ProductVariantRow')
class ProductVariants extends Table with CommonFields {
  /// Producto propietario de la variante. La cascada solo protege limpiezas
  /// tecnicas de proyecciones; no representa un borrado de negocio.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// Precio de venta entero expresado en la unidad monetaria menor.
  IntColumn get salePriceMinor => integer()();

  /// Indica que esta es la variante inicial elegida por omision.
  BoolColumn get isDefault => boolean()();

  /// Posicion dentro del producto; el alta sencilla siempre comienza en cero.
  IntColumn get sortOrder => integer()();

  /// Comportamiento de inventario; este alcance solo materializa `none`.
  TextColumn get inventoryBehavior =>
      text().withDefault(const Constant('none'))();

  /// Activa el control de inventario para esta variante. El valor legado
  /// `inventory_behavior = none` se migra a `false` sin crear recursos.
  BoolColumn get inventoryEnabled =>
      boolean().withDefault(const Constant(false))();

  /// Recurso afectado directamente por la venta, elegido explícitamente.
  TextColumn get directInventoryItemId => text().nullable().references(
    InventoryItems,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Cantidad atómica consumida por venta cuando el vínculo directo está activo.
  IntColumn get directQuantityAtomic => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {productId, sortOrder},
  ];
}
