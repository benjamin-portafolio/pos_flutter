import '../edicion_masiva/cambio_explicito.dart';
import 'articulo_import_actualizacion.dart';
import 'articulo_import_producto_error.dart';
import 'articulo_import_producto_local.dart';
import 'articulo_import_variante_local.dart';
import 'articulo_import_solicitud.dart';
import '../../domain/articulos/sale_mode.dart';
import '../../domain/inventario/unidad_inventario.dart';

/// Categoría del catálogo disponible para resolver la columna `categoria`.
///
/// La importación nunca crea categorías: si el nombre del archivo no está en
/// esta lista, la fila es un error.
class ArticuloImportCategoria {
  const ArticuloImportCategoria({required this.id, required this.nombre});

  final String id;
  final String nombre;
}

/// Foto del catálogo que la validación necesita para decidir qué filas son
/// válidas, resuelta mediante una lectura local específica.
///
/// El parser recibe categorías, unidades, nombres y productos involucrados.
/// No conoce Drift ni consulta historial o saldos.
class ArticuloImportCatalogo {
  const ArticuloImportCatalogo({
    this.categorias = const <ArticuloImportCategoria>[],
    this.unidades = const <UnidadInventario>[],
    this.nombresArticulos = const <String>{},
    this.productosPorId = const {},
    this.variantesPorId = const {},
  });

  final List<ArticuloImportCategoria> categorias;
  final List<UnidadInventario> unidades;

  /// Nombres activos para rechazar altas duplicadas, sin resolver identidad.
  final Set<String> nombresArticulos;
  final Map<String, ArticuloImportProductoLocal> productosPorId;
  final Map<String, ArticuloImportVarianteLocal> variantesPorId;
}

/// Problema del archivo, con el número de línea, la columna y el motivo.
///
/// [linea] es null cuando el problema es del encabezado o del archivo entero y
/// no de una fila concreta. La línea 1 es el encabezado, así que la primera
/// fila de datos es la 2.
class ArticuloImportError {
  const ArticuloImportError({
    required this.columna,
    required this.motivo,
    this.linea,
  });

  final int? linea;
  final String columna;
  final String motivo;

  /// Texto de una línea del reporte, para la lista de la pantalla.
  String get descripcion => linea == null ? columna : 'Línea $linea · $columna';

  /// El mismo error con su número de línea. Los errores de una fila se
  /// detectan sin saber todavía en qué línea del archivo están, así que el
  /// número se estampa al cerrar la fila.
  ArticuloImportError enLinea(int numero) =>
      ArticuloImportError(linea: numero, columna: columna, motivo: motivo);

  @override
  String toString() =>
      'ArticuloImportError(${linea ?? '-'}, $columna, $motivo)';
}

/// Variante de un producto ya validada, con los importes convertidos a
/// centavos y las existencias ya convertidas a átomos.
///
/// Alta: el id lo genera el command service al procesar el lote.
class ArticuloImportVariante {
  const ArticuloImportVariante({
    required this.linea,
    required this.sortOrder,
    this.offerPrice = const CambioExplicito.conservar(),
    required this.precioVentaMinor,
    this.nombre,
    this.precioCosteMinor,
    this.codigoBarras,
    this.seguimientoExistencias = false,
    this.existenciasAtomic = 0,
  });

  /// Línea del archivo de la que salió esta variante, para el reporte.
  final int linea;

  /// Posición dentro del producto, desde cero, siguiendo el orden de fila.
  final int sortOrder;

  final String? nombre;
  final int precioVentaMinor;
  final CambioExplicito<int?> offerPrice;
  final int? precioCosteMinor;
  final String? codigoBarras;
  final bool seguimientoExistencias;

  /// Saldo inicial en átomos de la unidad del recurso. Siempre 0 cuando la
  /// variante no tiene seguimiento, porque un saldo sin recurso no existe.
  final int existenciasAtomic;
}

/// Producto del archivo, agrupado por `nombre_articulo`.
///
/// Los datos derivados no los escribe el usuario: la cantidad de referencia la
/// impone el factor atómico de la unidad de venta (H8, H16) y la unidad del
/// recurso sale de la forma de venta (H9).
class ArticuloImportProducto {
  const ArticuloImportProducto({
    required this.nombre,
    required this.modoVenta,
    required this.variantes,
    this.categoriaId,
    this.unidadVentaId,
    this.cantidadReferenciaPrecioAtomic,
    this.unidadInventarioId,
  });

  final String nombre;
  final String? categoriaId;
  final SaleMode modoVenta;
  final String? unidadVentaId;
  final int? cantidadReferenciaPrecioAtomic;

  /// `piece` si la venta es por unidad, la misma unidad de venta si es por
  /// fracción (H9).
  final String? unidadInventarioId;

  final List<ArticuloImportVariante> variantes;
}

/// Clasificación independiente de altas, actualizaciones, omisiones y errores.
///
/// El archivo con problemas no se importa entero: la pantalla muestra este
/// reporte y pregunta si se importan solo las filas válidas.
class ArticuloImportReporte {
  const ArticuloImportReporte({
    this.productos = const <ArticuloImportProducto>[],
    this.errores = const <ArticuloImportError>[],
    this.productosConCambios = const [],
    this.productosSinCambios = const [],
    this.productosConErrores = const [],
    this.categorias = const [],
    this.delimitadorAmbiguo = false,
  });

  /// Requiere elegir separador y repetir toda la validación.
  final bool delimitadorAmbiguo;

  /// Exclusivamente altas; nunca incluye propuestas de actualización.
  final List<ArticuloImportProducto> productos;
  final List<ArticuloImportActualizacion> productosConCambios;
  final List<ArticuloImportActualizacion> productosSinCambios;
  final List<ArticuloImportError> errores;
  final List<ArticuloImportProductoError> productosConErrores;
  final List<ArticuloImportCategoria> categorias;

  /// Reporte de un archivo que no se puede ni leer: sin filas válidas y con el
  /// error que lo impide.
  factory ArticuloImportReporte.rechazando(ArticuloImportError error) =>
      ArticuloImportReporte(errores: <ArticuloImportError>[error]);

  /// Filas de alta válidas, una por variante.
  int get filasNuevas => productos.fold<int>(
    0,
    (total, producto) => total + producto.variantes.length,
  );

  int get filasConCambios =>
      productosConCambios.fold(0, (n, p) => n + p.variantes.length);
  int get filasSinCambios =>
      productosSinCambios.fold(0, (n, p) => n + p.variantes.length);
  int get filasValidas => filasNuevas + filasConCambios + filasSinCambios;
  int get filasExcluidas =>
      productosConErrores.fold(0, (n, p) => n + p.lineas.length);
  int get productosEjecutables => productos.length + productosConCambios.length;

  bool get hayErrores => errores.isNotEmpty;

  /// Un error sin línea impide entender el archivo, así que no tiene sentido
  /// ofrecer importar las filas válidas.
  bool get erroresEstructurales => errores.any((error) => error.linea == null);

  bool get importable =>
      (productos.isNotEmpty || productosConCambios.isNotEmpty) &&
      !erroresEstructurales;
}

/// Valida un archivo del contrato de columnas y devuelve el reporte.
///
/// No escribe nada: la escritura por lotes es una fase aparte. Tampoco toca la
/// base; recibe el catálogo ya resuelto.
abstract interface class ArticuloCatalogImportService {
  ArticuloImportSolicitud solicitarCatalogo(
    String contenido, {
    String? separador,
  });

  ArticuloImportReporte validar(
    String contenido, {
    required ArticuloImportCatalogo catalogo,
    String? separador,
  });
}
