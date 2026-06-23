import '../espacios/espacio.dart';

/// Contract defining operations related to spaces.
abstract class EspacioRepository {
  /// Stream to watch active spaces in real-time.
  Stream<List<Espacio>> watchEspacios();

  /// Retrieves the list of currently active spaces.
  Future<List<Espacio>> obtenerEspacios();
}
