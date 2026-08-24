import '../../domain/articulos/sale_configuration.dart';

class CrearArticuloCommand {
  const CrearArticuloCommand({
    required this.nombre,
    required this.precioVenta,
    this.categoriaId,
    this.saleConfiguration = const UnitSaleConfiguration(),
  });

  final String nombre;
  final String? categoriaId;
  final String precioVenta;
  final SaleConfiguration saleConfiguration;
}
