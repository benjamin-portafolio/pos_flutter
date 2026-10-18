import 'actualizar_articulo_variante_csv_command.dart';

/// Edición comercial parcial sobre la base que se mostró al confirmar el CSV.
/// No permite cambiar estructura, configuración de venta ni inventario.
class ActualizarArticuloCsvCommand {
  const ActualizarArticuloCsvCommand({
    required this.productId,
    required this.baseEventId,
    required this.nombre,
    required this.categoriaId,
    required this.variantes,
  });

  final String productId;
  final String baseEventId;
  final String nombre;
  final String? categoriaId;
  final List<ActualizarArticuloVarianteCsvCommand> variantes;
}
