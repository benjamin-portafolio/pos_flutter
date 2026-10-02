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
/// válidas, resuelta por quien llama.
///
/// El servicio de validación no lee la base: recibe las categorías, las unidades
/// y los nombres de artículos que ya existen, porque son las tres cosas contra
/// las que el archivo puede chocar. Así toda la validación se prueba sin Drift.
class ArticuloImportCatalogo {
  const ArticuloImportCatalogo({
    this.categorias = const <ArticuloImportCategoria>[],
    this.unidades = const <UnidadInventario>[],
    this.nombresArticulos = const <String>{},
  });

  final List<ArticuloImportCategoria> categorias;
  final List<UnidadInventario> unidades;

  /// Nombres de artículos que ya existen en el catálogo. Sin columna de
  /// identidad en el archivo (D5), el nombre es la única defensa contra un
  /// duplicado.
  final Set<String> nombresArticulos;
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
/// El id lo genera el command service al procesar el lote: el archivo nunca
/// lleva identidad (D4).
class ArticuloImportVariante {
  const ArticuloImportVariante({
    required this.linea,
    required this.sortOrder,
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

/// Resultado de validar el archivo: lo que se puede dar de alta y lo que no.
///
/// El archivo con problemas no se importa entero: la pantalla muestra este
/// reporte y pregunta si se importan solo las filas válidas.
class ArticuloImportReporte {
  const ArticuloImportReporte({
    this.productos = const <ArticuloImportProducto>[],
    this.errores = const <ArticuloImportError>[],
  });

  final List<ArticuloImportProducto> productos;
  final List<ArticuloImportError> errores;

  /// Reporte de un archivo que no se puede ni leer: sin filas válidas y con el
  /// error que lo impide.
  factory ArticuloImportReporte.rechazando(ArticuloImportError error) =>
      ArticuloImportReporte(errores: <ArticuloImportError>[error]);

  /// Filas válidas, una por variante.
  int get filasValidas => productos.fold<int>(
    0,
    (total, producto) => total + producto.variantes.length,
  );

  bool get hayErrores => errores.isNotEmpty;

  /// Un error sin línea impide entender el archivo, así que no tiene sentido
  /// ofrecer importar las filas válidas.
  bool get erroresEstructurales => errores.any((error) => error.linea == null);

  bool get importable => productos.isNotEmpty && !erroresEstructurales;
}

/// Valida un archivo del contrato de columnas y devuelve el reporte.
///
/// No escribe nada: la escritura por lotes es una fase aparte. Tampoco toca la
/// base; recibe el catálogo ya resuelto.
abstract interface class ArticuloCatalogImportService {
  ArticuloImportReporte validar(
    String contenido, {
    required ArticuloImportCatalogo catalogo,
  });
}
