import 'visibilidad_espacio.dart';

class Espacio {
  const Espacio({
    required this.id,
    required this.nombre,
    required this.identificacion,
    required this.visibilidad,
  });

  final String id;
  final String nombre;
  final String? identificacion;
  final VisibilidadEspacio visibilidad;
}
