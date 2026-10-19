import 'clave_variante.dart';
import 'fila_catalogo_masivo.dart';

class LecturaEdicionMasiva {
  LecturaEdicionMasiva({
    required Map<ClaveVariante, FilaCatalogoMasivo> filas,
    required Set<String> proveedoresActivos,
  }) : filas = Map.unmodifiable(filas),
       proveedoresActivos = Set.unmodifiable(proveedoresActivos);

  final Map<ClaveVariante, FilaCatalogoMasivo> filas;
  final Set<String> proveedoresActivos;
}
