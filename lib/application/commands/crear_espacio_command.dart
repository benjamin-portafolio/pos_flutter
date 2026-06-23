import '../../domain/espacios/visibilidad_espacio.dart';

class CrearEspacioCommand {
  const CrearEspacioCommand({
    required this.nombre,
    required this.identificacion,
    required this.visibilidad,
  });

  final String nombre;
  final String? identificacion;
  final VisibilidadEspacio visibilidad;
}
