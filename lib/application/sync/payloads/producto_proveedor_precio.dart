import 'supplier_json.dart';

/// Precio vigente de un proveedor para una variante, sin modificar sus costos.
class ProductoProveedorPrecio {
  ProductoProveedorPrecio({
    required String supplierId,
    required int quotedPriceMinor,
    required int quotedAtMs,
  }) : supplierId = SupplierJson.uuid(supplierId, 'supplier_id'),
       quotedPriceMinor = SupplierJson.integer(
         quotedPriceMinor,
         'quoted_price_minor',
       ),
       quotedAtMs = SupplierJson.integer(quotedAtMs, 'quoted_at_ms', min: 1);

  final String supplierId;
  final int quotedPriceMinor;

  /// Instante UTC en milisegundos desde Unix; no resuelve conflictos por reloj.
  final int quotedAtMs;

  factory ProductoProveedorPrecio.fromJson(Map<String, Object?> json) =>
      ProductoProveedorPrecio(
        supplierId: SupplierJson.uuid(json['supplier_id'], 'supplier_id'),
        quotedPriceMinor: SupplierJson.integer(
          json['quoted_price_minor'],
          'quoted_price_minor',
        ),
        quotedAtMs: SupplierJson.integer(
          json['quoted_at_ms'],
          'quoted_at_ms',
          min: 1,
        ),
      );

  Map<String, Object?> toJson() => {
    'supplier_id': supplierId,
    'quoted_price_minor': quotedPriceMinor,
    'quoted_at_ms': quotedAtMs,
  };

  /// null conserva ausencia legada; [] representa un conjunto vacío conocido.
  static List<ProductoProveedorPrecio>? parseVariant(
    Map<String, Object?> json,
  ) {
    if (!json.containsKey('suppliers')) return null;
    final values = json['suppliers'];
    if (values is! List) {
      throw const FormatException('suppliers debe ser un arreglo, nunca null.');
    }
    return validate([
      for (final value in values)
        ProductoProveedorPrecio.fromJson(
          SupplierJson.object(value, 'suppliers[]'),
        ),
    ]);
  }

  static List<ProductoProveedorPrecio>? validate(
    List<ProductoProveedorPrecio>? values,
  ) {
    if (values == null) return null;
    final ids = <String>{};
    for (final value in values) {
      if (!ids.add(value.supplierId)) {
        throw const FormatException(
          'Un proveedor no puede repetirse en la misma variante.',
        );
      }
    }
    final sorted = List<ProductoProveedorPrecio>.of(values)
      ..sort((a, b) => a.supplierId.compareTo(b.supplierId));
    return List.unmodifiable(sorted);
  }

  static bool sameList(
    List<ProductoProveedorPrecio>? a,
    List<ProductoProveedorPrecio>? b,
  ) {
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    final byId = {for (final value in b) value.supplierId: value};
    return a.every((value) {
      final other = byId[value.supplierId];
      return other != null &&
          value.quotedPriceMinor == other.quotedPriceMinor &&
          value.quotedAtMs == other.quotedAtMs;
    });
  }
}
