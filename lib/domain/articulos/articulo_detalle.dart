import 'sale_configuration.dart';
import 'variante_detalle.dart';

class ArticuloDetalle {
  const ArticuloDetalle({
    this.lastEventId,
    required this.nombre,
    required this.categoriaId,
    required this.saleConfiguration,
    required this.variantes,
  });
  final String? lastEventId;
  final String nombre;
  final String? categoriaId;
  final SaleConfiguration saleConfiguration;
  final List<VarianteDetalle> variantes;
}
