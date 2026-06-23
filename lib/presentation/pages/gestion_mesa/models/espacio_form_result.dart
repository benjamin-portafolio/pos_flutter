import 'package:flutter/foundation.dart';

import '../../../../domain/espacios/visibilidad_espacio.dart';

@immutable
class EspacioFormResult {
  const EspacioFormResult({
    required this.titulo,
    required this.identificacion,
    required this.visibilidad,
  });

  final String titulo;
  final String identificacion;
  final VisibilidadEspacio visibilidad;
}
