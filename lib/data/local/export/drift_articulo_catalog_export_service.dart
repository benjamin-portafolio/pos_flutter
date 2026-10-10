import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../application/config/app_config_store.dart';
import '../../../application/export/articulo_catalog_export_service.dart';
import '../drift/app_database.dart';
import 'articulo_catalog_csv.dart';
import 'articulo_catalog_pdf.dart';

/// Escribe el catálogo del dispositivo en un archivo del directorio temporal y
/// devuelve su ruta.
///
/// El archivo lo comparte la pantalla con `share_plus`, que necesita el
/// `BuildContext` para anclar el diálogo. Aquí no hay UI: solo lectura del
/// catálogo local y escritura del archivo.
///
/// Los dos formatos salen de la misma lectura, así que el CSV y el PDF nunca
/// pueden discrepar sobre qué productos existen. El PDF además toma del
/// `AppConfig` el nombre del negocio y el teléfono del pie.
class DriftArticuloCatalogExportService
    implements ArticuloCatalogExportService {
  DriftArticuloCatalogExportService({
    required ProductoDao productoDao,
    required AppConfigStore configStore,
    Future<Directory> Function()? directorio,
    DateTime Function()? ahora,
  }) : _productoDao = productoDao,
       _configStore = configStore,
       _directorio = directorio ?? getTemporaryDirectory,
       _ahora = ahora ?? DateTime.now;

  static const _nombreCatalogo = 'catalogo';
  static const _nombrePlantilla = 'plantilla_catalogo.csv';
  static const _nombreNotas = 'catalogo_columnas.csv';

  final ProductoDao _productoDao;
  final AppConfigStore _configStore;
  final Future<Directory> Function() _directorio;
  final DateTime Function() _ahora;

  @override
  Future<ArticuloExportArchivo> exportarCatalogo(
    ArticuloExportFiltro filtro,
  ) async {
    final lectura = await _leer(filtro);
    return _escribir(
      nombreArchivo: '${_nombreCatalogo}_${_fecha()}.csv',
      bytes: ArticuloCatalogCsv.bytes(
        ArticuloCatalogCsv.catalogo(lectura.filas),
      ),
      productos: lectura.productos,
      filas: ArticuloCatalogCsv.filasExportables(lectura.filas).length,
      productosTotales: lectura.productosTotales,
    );
  }

  @override
  Future<ArticuloExportArchivo> exportarCatalogoPdf(
    ArticuloExportFiltro filtro,
  ) async {
    final lectura = await _leer(filtro);
    final config = await _configStore.readConfig();
    final documento = ArticuloCatalogPdf.documento(
      lectura.filas,
      negocio: config.businessName,
      telefono: config.businessPhone,
      generado: _ahora(),
    );
    return _escribir(
      nombreArchivo: '${_nombreCatalogo}_${_fecha()}.pdf',
      bytes: await ArticuloCatalogPdf.bytes(documento),
      productos: lectura.productos,
      filas: documento.lineas,
      productosTotales: lectura.productosTotales,
    );
  }

  @override
  Future<ArticuloExportArchivo> exportarPlantilla() {
    return _escribir(
      nombreArchivo: _nombrePlantilla,
      bytes: ArticuloCatalogCsv.bytes(ArticuloCatalogCsv.plantilla()),
      productos: ArticuloCatalogCsv.productosPlantilla,
      filas: ArticuloCatalogCsv.filasPlantilla,
    );
  }

  @override
  Future<ArticuloExportArchivo> exportarNotasColumnas() {
    return _escribir(
      nombreArchivo: _nombreNotas,
      bytes: ArticuloCatalogCsv.bytes(ArticuloCatalogCsv.notasColumnas()),
      productos: 0,
      filas: 0,
    );
  }

  /// Lectura del catálogo para un filtro, con los conteos que la pantalla
  /// muestra. La comparten el CSV y el PDF para que ninguno tenga su propia
  /// forma de contar.
  ///
  /// El total sin filtros solo se lee cuando hay filtros activos, porque sin
  /// filtros la exportación ya es el catálogo completo y la segunda lectura
  /// sería un gasto inútil (H18).
  Future<_LecturaCatalogo> _leer(ArticuloExportFiltro filtro) async {
    final filas = await _leerCatalogo(
      busqueda: filtro.busqueda,
      categoriaIds: filtro.categoryIds,
      incluirSinCategoria: filtro.incluirSinCategoria,
    );
    final totalSinFiltros = filtro.hayFiltros
        ? ArticuloCatalogCsv.productosDelArchivo(
            await _leerCatalogo(
              busqueda: '',
              categoriaIds: const <String>{},
              incluirSinCategoria: false,
            ),
          ).length
        : null;
    return _LecturaCatalogo(
      filas: filas,
      productos: ArticuloCatalogCsv.productosDelArchivo(filas).length,
      productosTotales: totalSinFiltros,
    );
  }

  Future<List<ProductoListadoRow>> _leerCatalogo({
    required String busqueda,
    required Set<String> categoriaIds,
    required bool incluirSinCategoria,
  }) {
    return _productoDao
        .watchProductosListado(
          busqueda: busqueda,
          categoriaIds: categoriaIds,
          incluirSinCategoria: incluirSinCategoria,
        )
        .first;
  }

  Future<ArticuloExportArchivo> _escribir({
    required String nombreArchivo,
    required List<int> bytes,
    required int productos,
    required int filas,
    int? productosTotales,
  }) async {
    final destino = await _directorio();
    final archivo = File(path.join(destino.path, nombreArchivo));
    await archivo.writeAsBytes(bytes, flush: true);
    return ArticuloExportArchivo(
      ruta: archivo.path,
      productos: productos,
      filas: filas,
      productosTotales: productosTotales,
    );
  }

  /// El nombre del archivo lleva la fecha, para no sobrescribir a ciegas el
  /// catálogo de una exportación anterior.
  String _fecha() {
    final momento = _ahora();
    final mes = momento.month.toString().padLeft(2, '0');
    final dia = momento.day.toString().padLeft(2, '0');
    return '${momento.year}-$mes-$dia';
  }
}

/// Foto del catálogo con los conteos ya resueltos, compartida por los dos
/// formatos.
class _LecturaCatalogo {
  const _LecturaCatalogo({
    required this.filas,
    required this.productos,
    required this.productosTotales,
  });

  final List<ProductoListadoRow> filas;
  final int productos;
  final int? productosTotales;
}
