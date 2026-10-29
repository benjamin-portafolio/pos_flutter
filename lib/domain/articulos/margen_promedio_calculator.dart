/// Variante elegible para calcular el margen de un producto dentro de una
/// agrupación (categoría o proveedor).
typedef MargenPromedioVariante = ({
  String grupoId,
  String productoId,
  int precioVentaMenor,
  int? costoEstandarMenor,
});

/// Calcula el margen porcentual promedio sobre venta.
///
/// Primero promedia las variantes elegibles de cada producto y después los
/// productos elegibles de cada agrupación. Un producto cuenta una sola vez por
/// agrupación, sin ponderar por existencias, ventas ni compras.
class MargenPromedioCalculator {
  const MargenPromedioCalculator();

  /// Devuelve el margen de cada agrupación con datos elegibles.
  ///
  /// Un costo `null` es desconocido y se excluye; un costo cero participa.
  /// Un precio de venta no positivo no permite calcular el porcentaje y se
  /// excluye. Las agrupaciones sin datos no aparecen en el resultado.
  Map<String, double> calcular(Iterable<MargenPromedioVariante> variantes) {
    final porProducto = <({String grupoId, String productoId}), _Acumulado>{};
    for (final variante in variantes) {
      if (variante.precioVentaMenor <= 0) continue;
      final costo = variante.costoEstandarMenor;
      if (costo == null) continue;
      final margen =
          (variante.precioVentaMenor - costo) / variante.precioVentaMenor * 100;
      porProducto
          .putIfAbsent((
            grupoId: variante.grupoId,
            productoId: variante.productoId,
          ), _Acumulado.new)
          .agregar(margen);
    }

    final porGrupo = <String, _Acumulado>{};
    for (final entry in porProducto.entries) {
      porGrupo
          .putIfAbsent(entry.key.grupoId, _Acumulado.new)
          .agregar(entry.value.promedio);
    }

    return Map.unmodifiable({
      for (final entry in porGrupo.entries) entry.key: entry.value.promedio,
    });
  }
}

class _Acumulado {
  double _suma = 0;
  int _cantidad = 0;

  void agregar(double valor) {
    _suma += valor;
    _cantidad++;
  }

  double get promedio => _suma / _cantidad;
}
