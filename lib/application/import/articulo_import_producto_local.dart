import '../../domain/articulos/sale_mode.dart';
import 'articulo_import_variante_local.dart';

/// Foto ligera del producto completo para revisar, incluida su base observada.
/// No sustituye al snapshot de persistencia que deberá releerse al guardar.
class ArticuloImportProductoLocal {
  const ArticuloImportProductoLocal({
    required this.id,
    required this.activo,
    required this.nombre,
    required this.modoVenta,
    required this.variantes,
    this.categoriaId,
    this.unidadVentaId,
    this.cantidadReferenciaPrecioAtomic,
    this.lastEventId,
  });
  final String id;
  final bool activo;
  final String nombre;
  final String? categoriaId;
  final SaleMode modoVenta;
  final String? unidadVentaId;
  final int? cantidadReferenciaPrecioAtomic;
  final String? lastEventId;
  final List<ArticuloImportVarianteLocal> variantes;
}
