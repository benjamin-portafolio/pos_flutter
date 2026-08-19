import 'unidad_inventario.dart';

class RecursoInventarioListado {
  const RecursoInventarioListado({
    required this.id,
    required this.nombre,
    required this.activo,
    required this.existenciaAtomica,
    required this.unidadPredeterminada,
    required this.vinculadoAVariante,
    required this.cantidadRecetas,
    required this.nombresVariantesVinculadas,
  });

  final String id;
  final String nombre;
  final bool activo;
  final int existenciaAtomica;
  final UnidadInventario unidadPredeterminada;
  final bool vinculadoAVariante;
  final int cantidadRecetas;
  final List<String> nombresVariantesVinculadas;

  bool get usadoEnRecetas => cantidadRecetas > 0;
}
