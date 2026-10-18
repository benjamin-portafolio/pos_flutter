import 'articulo_catalog_import_service.dart';
import 'articulo_import_solicitud.dart';

/// Lee una foto consistente y ligera, sin efectos de negocio ni eventos.
abstract interface class ArticuloImportCatalogReader {
  Future<ArticuloImportCatalogo> leer(ArticuloImportSolicitud solicitud);
}
