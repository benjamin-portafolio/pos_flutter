import 'producto_creado_payload.dart';

/// Estado completo antes y después para edición atómica y reversión local.
class ProductoActualizadoPayload {
  ProductoActualizadoPayload({
    required this.baseEventId,
    required this.before,
    required this.after,
  }) {
    if (baseEventId.trim().isEmpty) {
      throw const FormatException('Falta el evento base.');
    }
    if (before.saleConfiguration != after.saleConfiguration) {
      throw const FormatException('No se puede cambiar la forma de venta.');
    }
    final ids = after.variantes.map((v) => v.id).toSet();
    if (!before.variantes.every((v) => ids.contains(v.id))) {
      throw const FormatException(
        'La actualización debe conservar las variantes existentes.',
      );
    }
  }
  static const aggregateType = 'product';
  static const eventType = 'producto_actualizado';
  final String baseEventId;
  final ProductoCreadoPayload before;
  final ProductoCreadoPayload after;
  factory ProductoActualizadoPayload.fromJson(Map<String, Object?> json) {
    if (json['base_event_id'] is! String ||
        json['before'] is! Map ||
        json['after'] is! Map) {
      throw const FormatException('Actualización de producto inválida.');
    }
    return ProductoActualizadoPayload(
      baseEventId: json['base_event_id'] as String,
      before: ProductoCreadoPayload.fromJson(
        Map<String, Object?>.from(json['before'] as Map),
      ),
      after: ProductoCreadoPayload.fromJson(
        Map<String, Object?>.from(json['after'] as Map),
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
    ?after.dependenciaCategoria?.dependsOnEventId,
    ...after.dependenciasInventario
        .map((d) => d.dependsOnEventId)
        .whereType<String>(),
  };
  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'before': before.toJson(),
    'after': after.toJson(),
  };
}
