/// Lecturas observables del margen porcentual promedio sobre venta.
///
/// Cada mapa asocia el id de una categoría o proveedor con su margen promedio.
/// Una agrupación sin datos elegibles no aparece en el mapa.
abstract interface class MargenPromedioRepository {
  /// Margen promedio de los productos vinculados directamente a cada categoría.
  Stream<Map<String, double>> watchMargenPromedioPorCategoria();

  /// Margen promedio de las variantes vinculadas a cada proveedor, usando su
  /// costo estándar y no el precio informado por el proveedor.
  Stream<Map<String, double>> watchMargenPromedioPorProveedor();
}
