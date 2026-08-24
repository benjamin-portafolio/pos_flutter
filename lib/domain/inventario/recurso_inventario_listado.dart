import 'unidad_inventario.dart';

class RecursoInventarioListado {
  const RecursoInventarioListado({
    required this.id,
    required this.nombre,
    required this.activo,
    required this.existenciaAtomica,
    required this.unidadPredeterminada,
  });

  final String id;
  final String nombre;
  final bool activo;
  final int existenciaAtomica;
  final UnidadInventario unidadPredeterminada;
}
