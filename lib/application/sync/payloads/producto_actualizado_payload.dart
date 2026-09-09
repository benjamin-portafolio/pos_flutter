import 'producto_creado_payload.dart';

/// Estado completo antes y después para edición atómica y reversión local.
class ProductoActualizadoPayload {
  ProductoActualizadoPayload({
    required this.baseEventId,
    required this.before,
    required this.after,
    this.deleteProduct = false,
  }) {
    if (baseEventId.trim().isEmpty) {
      throw const FormatException('Falta el evento base.');
    }
    if (before.saleConfiguration != after.saleConfiguration) {
      throw const FormatException('No se puede cambiar la forma de venta.');
    }
    if (deleteProduct && !sameState(before, after)) {
      throw const FormatException(
        'El borrado debe conservar el estado anterior.',
      );
    }
  }
  static const aggregateType = 'product';
  static const eventType = 'producto_actualizado';

  /// La eliminación conserva la base y serializa after=null (producto ausente).
  final bool deleteProduct;
  Iterable<ProductoCreadoVariante> get removedVariants =>
      before.variantes.where(
        (v) => deleteProduct || !after.variantes.any((next) => next.id == v.id),
      );
  final String baseEventId;
  final ProductoCreadoPayload before;
  final ProductoCreadoPayload after;
  factory ProductoActualizadoPayload.fromJson(Map<String, Object?> json) {
    if ((json.containsKey('delete_product') &&
            json['delete_product'] is! bool) ||
        json['base_event_id'] is! String ||
        json['before'] is! Map ||
        !json.containsKey('after') ||
        (json['delete_product'] == true
            ? json['after'] != null
            : json['after'] is! Map)) {
      throw const FormatException('Actualización de producto inválida.');
    }
    return ProductoActualizadoPayload(
      baseEventId: json['base_event_id'] as String,
      deleteProduct: json['delete_product'] == true,
      before: ProductoCreadoPayload.fromJson(
        Map<String, Object?>.from(json['before'] as Map),
      ),
      after: ProductoCreadoPayload.fromJson(
        Map<String, Object?>.from(
          (json['delete_product'] == true ? json['before'] : json['after'])
              as Map,
        ),
      ),
    );
  }

  /// Compara el estado de negocio sin depender del orden de componentes JSON.
  static bool sameState(
    ProductoCreadoPayload left,
    ProductoCreadoPayload right,
  ) {
    if (left.nombre != right.nombre ||
        left.categoriaId != right.categoriaId ||
        left.saleConfiguration != right.saleConfiguration ||
        left.variantes.length != right.variantes.length) {
      return false;
    }
    final byId = {for (final v in right.variantes) v.id: v};
    for (final v in left.variantes) {
      final other = byId[v.id];
      if (other == null ||
          v.nombre != other.nombre ||
          v.nameKey != other.nameKey ||
          v.precioVentaMenor != other.precioVentaMenor ||
          v.costoEstandarMenor != other.costoEstandarMenor ||
          v.inventoryItemId != other.inventoryItemId ||
          v.esPredeterminada != other.esPredeterminada ||
          v.orden != other.orden ||
          v.componentesReceta.length != other.componentesReceta.length) {
        return false;
      }
      final recipe = {
        for (final c in other.componentesReceta)
          c.inventoryItemId: c.quantityAtomic,
      };
      if (v.componentesReceta.any(
        (c) => recipe[c.inventoryItemId] != c.quantityAtomic,
      )) {
        return false;
      }
    }
    return true;
  }

  Set<String> get dependencyEventIds => {
    baseEventId,
    if (!deleteProduct) ?after.dependenciaCategoria?.dependsOnEventId,
    if (!deleteProduct)
      ...after.dependenciasInventario
          .map((d) => d.dependsOnEventId)
          .whereType<String>(),
  };
  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    if (deleteProduct) 'delete_product': true,
    'before': before.toJson(),
    // Clientes anteriores rechazan after=null en lugar de ignorar el borrado.
    'after': deleteProduct ? null : after.toJson(),
  };
}
