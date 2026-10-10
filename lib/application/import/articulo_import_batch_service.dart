import '../commands/articulos/crear_articulo_command.dart';
import '../commands/articulos/crear_articulo_variante_command.dart';
import '../commands/articulos/producto_command_service.dart';
import '../../domain/articulos/sale_configuration.dart';
import '../../domain/articulos/sale_mode.dart';
import '../../domain/inventario/inventory_quantity_codec.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';
import 'articulo_catalog_import_service.dart';
import 'articulo_import_lote_fallido.dart';
import 'articulo_import_progreso.dart';

/// Ejecuta productos ya revisados y confirmados por la presentación. El alta y
/// sus eventos siguen siendo responsabilidad de ProductoCommandService.
class ArticuloImportBatchService {
  ArticuloImportBatchService({
    required ProductoCommandService productoCommandService,
    required UnidadInventarioRepository unidadInventarioRepository,
  }) : _productos = productoCommandService,
       _unidades = unidadInventarioRepository;

  static const productosPorLote = 50;
  final ProductoCommandService _productos;
  final UnidadInventarioRepository _unidades;
  static const _cantidades = InventoryQuantityCodec();

  Future<ArticuloImportProgreso> importar(
    List<ArticuloImportProducto> productos, {
    required void Function(ArticuloImportProgreso) onProgress,
  }) async {
    final pendientes = List<ArticuloImportProducto>.of(productos);
    final unidades = {
      for (final unidad in await _unidades.obtenerUnidadesActivas())
        unidad.id: unidad,
    };
    final totalLotes =
        (pendientes.length + productosPorLote - 1) ~/ productosPorLote;
    var procesados = 0;
    var importados = 0;
    var fallidos = 0;
    final errores = <ArticuloImportLoteFallido>[];
    ArticuloImportProgreso progreso() => ArticuloImportProgreso(
      lotesTotales: totalLotes,
      productosTotales: pendientes.length,
      lotesProcesados: procesados,
      productosImportados: importados,
      productosFallidos: fallidos,
      lotesFallidos: List.unmodifiable(errores),
    );
    onProgress(progreso());
    for (
      var inicio = 0;
      inicio < pendientes.length;
      inicio += productosPorLote
    ) {
      final fin = (inicio + productosPorLote).clamp(0, pendientes.length);
      final lote = pendientes.sublist(inicio, fin);
      try {
        await _productos.crearArticulosLote([
          for (final producto in lote) _command(producto, unidades),
        ]);
        importados += lote.length;
      } catch (error) {
        fallidos += lote.length;
        errores.add(
          ArticuloImportLoteFallido(
            numero: procesados + 1,
            productos: List.unmodifiable(
              lote.map((producto) => producto.nombre),
            ),
            lineas: List.unmodifiable([
              for (final producto in lote)
                for (final variante in producto.variantes) variante.linea,
            ]),
            motivo: _motivo(error),
          ),
        );
      }
      procesados++;
      onProgress(progreso());
    }
    return progreso();
  }

  CrearArticuloCommand _command(
    ArticuloImportProducto producto,
    Map<String, UnidadInventario> unidades,
  ) => CrearArticuloCommand.conVariantes(
    nombre: producto.nombre,
    categoriaId: producto.categoriaId,
    saleConfiguration: producto.modoVenta == SaleMode.unit
        ? const UnitSaleConfiguration()
        : MeasuredSaleConfiguration(
            saleUnitId: producto.unidadVentaId!,
            priceReferenceQuantityAtomic:
                producto.cantidadReferenciaPrecioAtomic!,
          ),
    variantes: [
      for (final variante in producto.variantes)
        CrearArticuloVarianteCommand(
          nombre: variante.nombre,
          precioVenta: _dinero(variante.precioVentaMinor),
          costoEstandar: variante.precioCosteMinor == null
              ? null
              : _dinero(variante.precioCosteMinor!),
          codigoBarras: variante.codigoBarras,
          inventoryUnitId: variante.seguimientoExistencias
              ? producto.unidadInventarioId
              : null,
          initialStockQuantity: variante.seguimientoExistencias
              ? _cantidades.formatAtomic(
                  variante.existenciasAtomic,
                  unidades[producto.unidadInventarioId] ??
                      (throw StateError(
                        'La unidad de inventario ya no está disponible.',
                      )),
                )
              : null,
        ),
    ],
  );

  String _motivo(Object error) => switch (error) {
    FormatException() => error.message,
    StateError() => error.message,
    ArgumentError() =>
      error.message?.toString() ?? 'Los datos del lote no son válidos.',
    _ =>
      'No se pudo guardar el lote. Revisa los artículos e inténtalo de nuevo.',
  };

  // Reconstrucción decimal exacta: la regla half-up ya se aplicó al leer el CSV.
  String _dinero(int minor) =>
      '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
}
