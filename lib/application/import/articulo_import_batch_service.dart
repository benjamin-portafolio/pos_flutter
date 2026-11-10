import '../edicion_masiva/cambio_explicito.dart';
import '../commands/articulos/crear_articulo_command.dart';
import '../commands/articulos/crear_articulo_variante_command.dart';
import '../commands/articulos/producto_command_service.dart';
import '../commands/articulos/actualizar_articulo_csv_command.dart';
import '../commands/articulos/actualizar_articulo_variante_csv_command.dart';
import '../../domain/articulos/sale_configuration.dart';
import '../../domain/articulos/sale_mode.dart';
import '../../domain/inventario/inventory_quantity_codec.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';
import 'articulo_catalog_import_service.dart';
import 'articulo_import_lote_fallido.dart';
import 'articulo_import_progreso.dart';
import 'articulo_import_actualizacion.dart';
import 'articulo_import_eliminacion.dart';

/// Ejecuta altas, actualizaciones y eliminaciones; las omisiones se cuentan.
/// ProductoCommandService prepara y aplica cada lote en una transacción real.
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
    List<ArticuloImportActualizacion> actualizaciones = const [],
    List<ArticuloImportEliminacion> eliminaciones = const [],
    List<ArticuloImportActualizacion> omitidos = const [],
    required void Function(ArticuloImportProgreso) onProgress,
  }) async {
    final pendientes = [
      for (final producto in eliminaciones)
        _ProductoPendiente.eliminacion(producto),
      for (final producto in productos) _ProductoPendiente.alta(producto),
      for (final producto in actualizaciones)
        _ProductoPendiente.actualizacion(producto),
    ]..sort((a, b) => a.lineas.first.compareTo(b.lineas.first));
    final unidades = productos.isEmpty
        ? <String, UnidadInventario>{}
        : {
            for (final unidad in await _unidades.obtenerUnidadesActivas())
              unidad.id: unidad,
          };
    final totalLotes =
        (pendientes.length + productosPorLote - 1) ~/ productosPorLote;
    var procesados = 0;
    var importados = 0;
    var creados = 0;
    var actualizados = 0;
    var eliminados = 0;
    var sinCambios = omitidos.length;
    var fallidos = 0;
    final errores = <ArticuloImportLoteFallido>[];
    ArticuloImportProgreso progreso() => ArticuloImportProgreso(
      lotesTotales: totalLotes,
      productosTotales: pendientes.length,
      lotesProcesados: procesados,
      productosImportados: importados,
      productosCreados: creados,
      productosActualizados: actualizados,
      productosEliminados: eliminados,
      productosOmitidos: sinCambios,
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
        final resultado = await _productos.importarArticulosLote(
          eliminaciones: [
            for (final producto in lote)
              if (producto.eliminacion case final eliminacion?)
                (
                  productId: eliminacion.actual.id,
                  baseEventId:
                      eliminacion.actual.lastEventId ??
                      (throw StateError(
                        "El artículo no tiene una base confirmada.",
                      )),
                ),
          ],
          altas: [
            for (final producto in lote)
              if (producto.alta case final alta?) _command(alta, unidades),
          ],
          actualizaciones: [
            for (final producto in lote)
              if (producto.actualizacion case final actualizacion?)
                _actualizacionCommand(actualizacion),
          ],
        );
        creados += resultado.creados;
        actualizados += resultado.actualizados;
        eliminados += resultado.eliminados;
        sinCambios += resultado.sinCambios;
        importados +=
            resultado.creados + resultado.actualizados + resultado.eliminados;
      } catch (error) {
        fallidos += lote.length;
        errores.add(
          ArticuloImportLoteFallido(
            numero: procesados + 1,
            productos: List.unmodifiable(
              lote.map((producto) => producto.nombre),
            ),
            lineas: List.unmodifiable([
              for (final producto in lote) ...producto.lineas,
            ]),
            productIds: List.unmodifiable([
              for (final producto in lote)
                if (producto.actualizacion case final actualizacion?)
                  actualizacion.productId,
              for (final producto in lote)
                if (producto.eliminacion case final eliminacion?)
                  eliminacion.actual.id,
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

  ActualizarArticuloCsvCommand _actualizacionCommand(
    ArticuloImportActualizacion producto,
  ) => ActualizarArticuloCsvCommand(
    productId: producto.productId,
    baseEventId:
        producto.baseEventId ??
        (throw StateError('El artículo no tiene una base confirmada.')),
    nombre: producto.nombre,
    categoriaId: producto.categoriaId,
    variantes: [
      for (final variante in producto.variantes)
        ActualizarArticuloVarianteCsvCommand(
          variantId: variante.id,
          nombre: variante.nombre,
          offerPrice: variante.offerPrice,
          precioVentaMinor: variante.precioVentaMinor,
          precioCosteMinor: variante.precioCosteMinor,
          codigoBarras: variante.codigoBarras,
        ),
    ],
  );

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
          offerPrice: variante.offerPrice.establecer
              ? CambioExplicito.establecer(
                  variante.offerPrice.valor == null
                      ? null
                      : _dinero(variante.offerPrice.valor!),
                )
              : const CambioExplicito.conservar(),
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

  // Reconstrucción decimal exacta de los importes validados al leer el CSV.
  String _dinero(int minor) =>
      '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
}

class _ProductoPendiente {
  const _ProductoPendiente.alta(ArticuloImportProducto producto)
    : alta = producto,
      eliminacion = null,
      actualizacion = null;
  const _ProductoPendiente.actualizacion(ArticuloImportActualizacion producto)
    : actualizacion = producto,
      eliminacion = null,
      alta = null;
  const _ProductoPendiente.eliminacion(ArticuloImportEliminacion producto)
    : eliminacion = producto,
      alta = null,
      actualizacion = null;

  final ArticuloImportProducto? alta;
  final ArticuloImportEliminacion? eliminacion;
  final ArticuloImportActualizacion? actualizacion;
  String get nombre =>
      alta?.nombre ?? eliminacion?.actual.nombre ?? actualizacion!.nombre;
  List<int> get lineas => [
    if (eliminacion case final producto?) ...producto.lineas,
    if (alta case final producto?)
      for (final v in producto.variantes) v.linea,
    if (actualizacion case final producto?)
      for (final v in producto.variantes) v.linea,
  ];
}
