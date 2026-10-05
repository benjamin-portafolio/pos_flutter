import '../inventario/unidad_inventario.dart';
import 'sale_configuration.dart';

/// Candidato activo de una consulta exacta; un código puede tener varios.
class VariantePorCodigoBarras {
  const VariantePorCodigoBarras({
    required this.productoId,
    required this.varianteId,
    required this.nombreProducto,
    required this.nombreVariante,
    required this.codigoBarras,
    required this.precioVentaMenor,
    required this.saleConfiguration,
    required this.unidadVenta,
  });

  final String productoId;
  final String varianteId;
  final String nombreProducto;
  final String? nombreVariante;
  final String codigoBarras;
  final int precioVentaMenor;
  final SaleConfiguration saleConfiguration;
  final UnidadInventario? unidadVenta;
}
