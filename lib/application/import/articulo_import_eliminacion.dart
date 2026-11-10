import 'articulo_import_producto_local.dart';

/// Eliminación del producto completo contra la base mostrada en revisión.
class ArticuloImportEliminacion {
  const ArticuloImportEliminacion({required this.actual, required this.lineas});
  final ArticuloImportProductoLocal actual;
  final List<int> lineas;
}
