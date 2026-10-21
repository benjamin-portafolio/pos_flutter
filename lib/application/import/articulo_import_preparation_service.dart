import 'articulo_catalog_import_service.dart';
import 'articulo_import_catalog_reader.dart';

/// Coordina lectura y revisión puras. La escritura es una fase independiente.
class ArticuloImportPreparationService {
  const ArticuloImportPreparationService({
    required this.parser,
    required this.reader,
  });
  final ArticuloCatalogImportService parser;
  final ArticuloImportCatalogReader reader;

  Future<ArticuloImportReporte> preparar(
    String contenido, {
    String? separador,
  }) async {
    final solicitud = parser.solicitarCatalogo(contenido, separador: separador);
    if (solicitud.errores.isNotEmpty) {
      return ArticuloImportReporte(
        errores: solicitud.errores,
        delimitadorAmbiguo: solicitud.delimitadorAmbiguo,
      );
    }
    return parser.validar(
      contenido,
      catalogo: await reader.leer(solicitud),
      separador: separador,
    );
  }
}
