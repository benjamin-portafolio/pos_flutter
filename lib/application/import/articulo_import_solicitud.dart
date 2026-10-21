import 'articulo_catalog_import_service.dart';

/// Identidades opacas de un archivo estructuralmente válido; nunca se generan.
class ArticuloImportSolicitud {
  const ArticuloImportSolicitud({
    this.productIds = const {},
    this.variantIds = const {},
    this.errores = const [],
    this.delimitadorAmbiguo = false,
  });
  final bool delimitadorAmbiguo;
  final Set<String> productIds;
  final Set<String> variantIds;
  final List<ArticuloImportError> errores;
}
