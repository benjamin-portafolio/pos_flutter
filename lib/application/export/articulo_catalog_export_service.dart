/// Filtro de la pantalla de artículos aplicado a la exportación del catálogo.
///
/// Viaja como parámetro: la capa de presentación se lo pasa al servicio y el
/// servicio nunca lee estado de UI. Es el mismo filtro que usa el listado, con
/// los mismos nombres, para que el archivo salga con exactamente las filas que
/// el usuario está viendo.
class ArticuloExportFiltro {
  const ArticuloExportFiltro({
    this.busqueda = '',
    this.categoryIds = const <String>{},
    this.incluirSinCategoria = false,
  });

  /// Sin búsqueda ni categorías: sale todo el catálogo activo.
  static const sinFiltros = ArticuloExportFiltro();

  final String busqueda;
  final Set<String> categoryIds;
  final bool incluirSinCategoria;

  bool get hayFiltros =>
      busqueda.trim().isNotEmpty ||
      categoryIds.isNotEmpty ||
      incluirSinCategoria;
}

/// Archivo generado en el dispositivo, con las cifras que la pantalla necesita
/// para avisar al usuario de qué se está compartiendo.
class ArticuloExportArchivo {
  const ArticuloExportArchivo({
    required this.ruta,
    required this.productos,
    required this.filas,
    this.productosTotales,
  });

  /// Ruta del archivo en el directorio temporal del dispositivo.
  final String ruta;

  /// Artículos distintos incluidos en el archivo.
  final int productos;

  /// Líneas de datos del archivo, una por variante.
  final int filas;

  /// Artículos activos del catálogo sin ningún filtro. Es null cuando la
  /// exportación no lleva filtros, porque en ese caso [productos] ya es el
  /// total y una segunda lectura sería un gasto inútil.
  final int? productosTotales;
}

/// Genera el archivo del catálogo en el dispositivo.
///
/// El archivo de descarga es también la plantilla de carga: el mismo contrato
/// de columnas, validado por round-trip. No expone estado interno, ni
/// `product_id`, ni `version`, ni `last_event_id`.
abstract interface class ArticuloCatalogExportService {
  /// Escribe el catálogo con los filtros indicados, respetando los mismos
  /// joins y el mismo filtro de activos del listado.
  Future<ArticuloExportArchivo> exportarCatalogo(ArticuloExportFiltro filtro);

  /// Escribe el mismo catálogo como catálogo PDF para compartir con el cliente.
  ///
  /// Es una presentación, no un contrato: no participa del round-trip y no
  /// comparte columnas con el CSV más allá de leer el mismo catálogo (D8).
  Future<ArticuloExportArchivo> exportarCatalogoPdf(
    ArticuloExportFiltro filtro,
  );

  /// Escribe el contrato de columnas con ejemplos de llenado para reemplazar.
  Future<ArticuloExportArchivo> exportarPlantilla();

  /// Escribe `catalogo_columnas.csv`: una fila por columna con sus valores
  /// permitidos y su descripción. El CSV no admite comentarios, así que las
  /// notas viven en este segundo archivo.
  Future<ArticuloExportArchivo> exportarNotasColumnas();
}
