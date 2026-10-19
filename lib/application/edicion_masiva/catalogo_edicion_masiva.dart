import 'clave_variante.dart';
import 'fila_catalogo_masivo.dart';
import 'lectura_edicion_masiva.dart';

abstract interface class CatalogoEdicionMasiva {
  /// Página estable por nombre/ID; no hidrata snapshots ni todo el catálogo.
  Future<List<FilaCatalogoMasivo>> buscar({
    String busqueda = '',
    int limite = 100,
    int desplazamiento = 0,
  });

  /// Una sola foto consistente de los destinos y proveedores de la revisión.
  /// Destinos inexistentes, inactivos o con pertenencia incorrecta se omiten.
  Future<LecturaEdicionMasiva> leer(
    Set<ClaveVariante> claves, {
    Set<String> proveedorIds = const {},
  });
}
