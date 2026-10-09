import 'supplier_json.dart';

/// Existencia requerida; solo el alta local pendiente agrega dependencia causal.
class ProductoProveedorDependencia {
  ProductoProveedorDependencia({
    required String refId,
    String? dependsOnEventId,
  }) : refId = SupplierJson.uuid(refId, 'supplier.ref_id'),
       dependsOnEventId = dependsOnEventId == null
           ? null
           : SupplierJson.uuid(
               dependsOnEventId,
               'supplier.depends_on_event_id',
             );

  final String refId;
  final String? dependsOnEventId;

  factory ProductoProveedorDependencia.fromJson(Map<String, Object?> json) =>
      ProductoProveedorDependencia(
        refId: SupplierJson.uuid(json['ref_id'], 'supplier.ref_id'),
        dependsOnEventId: json['depends_on_event_id'] == null
            ? null
            : SupplierJson.uuid(
                json['depends_on_event_id'],
                'supplier.depends_on_event_id',
              ),
      );

  Map<String, Object?> toJson() => {
    'ref_type': 'supplier',
    'ref_id': refId,
    if (dependsOnEventId != null) 'depends_on_event_id': dependsOnEventId,
  };

  static List<ProductoProveedorDependencia> validate(
    Set<String> expectedIds,
    List<ProductoProveedorDependencia> values,
  ) {
    final ids = <String>{};
    for (final value in values) {
      if (!ids.add(value.refId)) {
        throw const FormatException('Dependencias supplier duplicadas.');
      }
    }
    if (ids.length != expectedIds.length || !ids.containsAll(expectedIds)) {
      throw const FormatException(
        'Las dependencias supplier deben coincidir con los proveedores de las variantes.',
      );
    }
    final sorted = List<ProductoProveedorDependencia>.of(values)
      ..sort((a, b) => a.refId.compareTo(b.refId));
    return List.unmodifiable(sorted);
  }
}
