import '../../../domain/articulos/sale_configuration.dart';
import 'crear_articulo_variante_command.dart';

class CrearArticuloCommand {
  const CrearArticuloCommand({
    required this.nombre,
    required this.precioVenta,
    this.categoriaId,
    this.saleConfiguration = const UnitSaleConfiguration(),
  }) : variantes = const [];

  const CrearArticuloCommand.conVariantes({
    required this.nombre,
    required this.variantes,
    this.categoriaId,
    this.saleConfiguration = const UnitSaleConfiguration(),
  }) : precioVenta = null;

  final String nombre;
  final String? categoriaId;
  final String? precioVenta;
  final List<CrearArticuloVarianteCommand> variantes;
  final SaleConfiguration saleConfiguration;
}
