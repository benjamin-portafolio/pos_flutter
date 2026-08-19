import 'unidad_inventario.dart';

class RecursoInventario {
  const RecursoInventario({
    required this.id,
    required this.nombre,
    required this.unidadPredeterminada,
    required this.activo,
    required this.version,
    required this.createdEventId,
    required this.lastEventId,
    required this.lastServerSequence,
  });

  final String id;
  final String nombre;
  final UnidadInventario unidadPredeterminada;
  final bool activo;
  final int version;
  final String? createdEventId;
  final String? lastEventId;
  final int? lastServerSequence;
}
