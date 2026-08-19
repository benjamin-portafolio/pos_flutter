import 'dimension_unidad.dart';

class UnidadInventario {
  const UnidadInventario({
    required this.id,
    required this.code,
    required this.nombre,
    required this.simbolo,
    required this.dimension,
    required this.factorAtomico,
    required this.maximosDecimales,
    required this.activa,
  });

  final String id;
  final String code;
  final String nombre;
  final String simbolo;
  final DimensionUnidad dimension;
  final int factorAtomico;
  final int maximosDecimales;
  final bool activa;
}
