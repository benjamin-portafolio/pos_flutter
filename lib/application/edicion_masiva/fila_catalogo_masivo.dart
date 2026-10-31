import '../../domain/articulos/proveedor_variante.dart';
import '../../domain/articulos/sale_configuration.dart';
import '../../domain/inventario/unidad_inventario.dart';
import 'base_entrada_masiva.dart';
import 'base_revision_masiva.dart';
import 'clave_variante.dart';

/// Lectura comercial ligera. No representa el snapshot completo de escritura.
/// Las relaciones leídas no promueven el conocimiento legado de proveedores;
/// esa semántica se conserva al releer el agregado en el comando de escritura.
class FilaCatalogoMasivo {
  FilaCatalogoMasivo({
    required this.clave,
    required this.baseProducto,
    required this.nombreProducto,
    required this.nombreVariante,
    this.ofertaMinor,
    required this.ventaMinor,
    required this.costoMinor,
    required this.configuracionVenta,
    required this.unidadVenta,
    required this.entrada,
    required this.impedimentoEntrada,
    required List<ProveedorVariante> proveedores,
  }) : proveedores = List.unmodifiable(proveedores);

  final ClaveVariante clave;
  final BaseRevisionMasiva baseProducto;
  final String nombreProducto;
  final String? nombreVariante;
  final int ventaMinor;
  final int? ofertaMinor;
  final int? costoMinor;
  final SaleConfiguration configuracionVenta;
  final UnidadInventario? unidadVenta;
  final BaseEntradaMasiva? entrada;
  final String? impedimentoEntrada;
  final List<ProveedorVariante> proveedores;
}
