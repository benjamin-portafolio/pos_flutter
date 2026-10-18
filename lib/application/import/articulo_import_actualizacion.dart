import 'articulo_import_producto_local.dart';
import 'articulo_import_variante_cambio.dart';

/// Propuesta parcial validada contra todas las variantes del producto.
/// Las omitidas permanecen en [actual]; este objeto no es un comando de alta.
class ArticuloImportActualizacion {
  const ArticuloImportActualizacion({
    required this.actual,
    required this.nombre,
    required this.categoriaId,
    required this.variantes,
  });
  final ArticuloImportProductoLocal actual;
  String get productId => actual.id;
  String? get baseEventId => actual.lastEventId;
  final String nombre;
  final String? categoriaId;
  final List<ArticuloImportVarianteCambio> variantes;
}
