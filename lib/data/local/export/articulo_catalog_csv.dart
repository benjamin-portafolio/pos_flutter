import 'dart:convert';
import 'dart:typed_data';

import '../../../domain/articulos/sale_mode.dart';
import '../../../domain/inventario/dimension_unidad.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/inventario/unidad_inventario.dart';
import '../drift/app_database.dart';

/// Compone el contrato de columnas del catálogo en CSV.
///
/// El mismo contrato sirve para descargar y para cargar (D3): el archivo de
/// descarga es la plantilla de carga. Formato: BOM UTF-8, delimitador `,` y una
/// línea por variante, con las variantes de un producto juntas.
///
/// Cada fila sale de una lectura de [ProductoListadoRow], que ya trae producto,
/// categoría, variante, unidad de venta, recurso, saldo y unidad de inventario.
/// Aquí no hay SQL: solo la traducción a las 10 columnas.
abstract final class ArticuloCatalogCsv {
  /// Coma como delimitador de la plantilla y del catálogo de carga y descarga.
  static const separador = ',';

  /// BOM UTF-8: Excel y LibreOffice abren el archivo con acentos correctos sin
  /// pedir nada.
  static const bom = '\uFEFF';

  /// Orden de columnas del contrato. El importador exige coincidencia exacta.
  static const columnas = <String>[
    'categoria',
    'nombre_articulo',
    'tipo_venta',
    'unidad_venta',
    'nombre_variante',
    'precio_venta',
    'precio_coste',
    'seguimiento_existencias',
    'existencias',
    'codigo_barras',
  ];

  static const _columnasNotas = <String>[
    'columna',
    'obligatoria',
    'valores_permitidos',
    'descripcion',
  ];

  /// Filas que el archivo puede escribir. Un producto sin variante activa no
  /// tiene precio de venta y por lo tanto no produce línea.
  static List<ProductoListadoRow> filasExportables(
    List<ProductoListadoRow> rows,
  ) {
    return rows.where((row) => row.variante != null).toList(growable: false);
  }

  /// Artículos distintos que el archivo escribe, en el orden en que aparecen.
  static Set<String> productosDelArchivo(List<ProductoListadoRow> rows) {
    return {for (final row in filasExportables(rows)) row.producto.id};
  }

  /// Catálogo completo: encabezado y una línea por variante, agrupadas por
  /// producto y en el orden de `sort_order`. No emite líneas en blanco.
  static String catalogo(List<ProductoListadoRow> rows) {
    final lineas = <String>[columnas.join(separador)];
    for (final grupo in _agruparPorProducto(filasExportables(rows))) {
      for (final row in grupo) {
        lineas.add(_campos(row).map(_campo).join(separador));
      }
    }
    return '${lineas.join('\n')}\n';
  }

  /// Contrato de columnas con ejemplos para reemplazar al preparar una carga.
  /// La categoría vacía permite usarlos sin depender del catálogo del equipo.
  static String plantilla() {
    final lineas = <String>[
      columnas.join(separador),
      for (final campos in _ejemplosPlantilla)
        campos.map(_campo).join(separador),
    ];
    return '${lineas.join('\n')}\n';
  }

  /// Filas de ejemplo incluidas en la plantilla, una por variante.
  static int get filasPlantilla => _ejemplosPlantilla.length;

  /// Artículos distintos de ejemplo incluidos en la plantilla.
  static int get productosPlantilla =>
      _ejemplosPlantilla.map((campos) => campos[1]).toSet().length;

  static const _ejemplosPlantilla = <List<String>>[
    [
      '',
      'Ejemplo - Café preparado',
      'unidad',
      '',
      '',
      '25.00',
      '',
      'no',
      '0',
      '',
    ],
    [
      '',
      'Ejemplo - Agua embotellada',
      'unidad',
      '',
      '',
      '18.00',
      '10.00',
      'si',
      '24',
      '000000000001',
    ],
    [
      '',
      'Ejemplo - Camiseta',
      'unidad',
      '',
      'Chica',
      '150.00',
      '90.00',
      'si',
      '10',
      '000000000002',
    ],
    [
      '',
      'Ejemplo - Camiseta',
      'unidad',
      '',
      'Grande',
      '170.00',
      '100.00',
      'si',
      '5',
      '000000000003',
    ],
    [
      '',
      'Ejemplo - Naranja',
      'fraccion',
      'kg',
      '',
      '30.00',
      '18.00',
      'si',
      '2.500',
      '',
    ],
  ];

  /// Notas de columna en un segundo archivo, porque el CSV no admite
  /// comentarios.
  static String notasColumnas() {
    final lineas = <String>[_columnasNotas.join(separador)];
    for (final nota in _notas) {
      lineas.add(
        [
          nota.columna,
          nota.obligatoria,
          nota.valoresPermitidos,
          nota.descripcion,
        ].map(_campo).join(separador),
      );
    }
    return '${lineas.join('\n')}\n';
  }

  /// Bytes del archivo: BOM UTF-8 y el texto del CSV.
  static Uint8List bytes(String csv) {
    return Uint8List.fromList(utf8.encode('$bom$csv'));
  }

  /// Las variantes de un producto quedan juntas y en el orden de `sort_order`,
  /// que es el mismo orden que usa el listado en pantalla.
  static List<List<ProductoListadoRow>> _agruparPorProducto(
    List<ProductoListadoRow> rows,
  ) {
    final grupos = <String, List<ProductoListadoRow>>{};
    for (final row in rows) {
      grupos
          .putIfAbsent(row.producto.id, () => <ProductoListadoRow>[])
          .add(row);
    }
    for (final grupo in grupos.values) {
      grupo.sort((left, right) {
        final porOrden = left.variante!.sortOrder.compareTo(
          right.variante!.sortOrder,
        );
        if (porOrden != 0) return porOrden;
        return left.variante!.id.compareTo(right.variante!.id);
      });
    }
    return grupos.values.toList(growable: false);
  }

  static List<String> _campos(ProductoListadoRow row) {
    final producto = row.producto;
    final variante = row.variante!;
    final porFraccion =
        SaleMode.fromCode(producto.saleMode) == SaleMode.measured;

    return <String>[
      row.categoria?.name ?? '',
      producto.name,
      porFraccion ? 'fraccion' : 'unidad',
      porFraccion ? (row.unidadVenta?.code ?? '') : '',
      variante.name ?? '',
      _importe(variante.salePriceMinor),
      variante.standardCostMinor == null
          ? ''
          : _importe(variante.standardCostMinor!),
      variante.inventoryItemId == null ? 'no' : 'si',
      _existencias(row),
      variante.barcode ?? '',
    ];
  }

  /// El saldo se escribe en la unidad del recurso, con los decimales que la
  /// unidad admite, y no en átomos: el archivo guarda magnitudes decimales.
  static String _existencias(ProductoListadoRow row) {
    final recurso = row.inventario;
    if (recurso == null) return '0';
    final unidad = row.unidadInventario;
    if (unidad == null) {
      throw StateError(
        'El recurso de inventario ${recurso.name} no tiene unidad predeterminada.',
      );
    }
    return const InventoryQuantityCodec().formatAtomic(
      row.saldo?.quantityOnHandAtomic ?? 0,
      _unidad(unidad),
    );
  }

  static String _importe(int minor) {
    final negativo = minor < 0;
    final magnitud = negativo ? -minor : minor;
    final centavos = (magnitud % 100).toString().padLeft(2, '0');
    return '${negativo ? '-' : ''}${magnitud ~/ 100}.$centavos';
  }

  /// Entrecomilla solo lo que rompería la separación: el delimitador, las
  /// comillas y los saltos de línea.
  static String _campo(String valor) {
    final necesitaComillas =
        valor.contains(separador) ||
        valor.contains('"') ||
        valor.contains('\n') ||
        valor.contains('\r');
    if (!necesitaComillas) return valor;
    return '"${valor.replaceAll('"', '""')}"';
  }

  static UnidadInventario _unidad(UnitRow fila) => UnidadInventario(
    id: fila.unitId,
    code: fila.code,
    nombre: fila.name,
    simbolo: fila.symbol,
    dimension: DimensionUnidad.fromCode(fila.dimension),
    factorAtomico: fila.atomicFactor,
    maximosDecimales: fila.maxFractionDigits,
    activa: fila.active,
  );
}

/// Nota de una columna del contrato, para el archivo `catalogo_columnas.csv`.
class _NotaColumna {
  const _NotaColumna({
    required this.columna,
    required this.obligatoria,
    required this.valoresPermitidos,
    required this.descripcion,
  });

  final String columna;
  final String obligatoria;
  final String valoresPermitidos;
  final String descripcion;
}

const _notas = <_NotaColumna>[
  _NotaColumna(
    columna: 'categoria',
    obligatoria: 'no',
    valoresPermitidos: 'nombre de una categoría existente',
    descripcion:
        'Vacío significa Sin categoría. La categoría debe existir: no se crean categorías al importar.',
  ),
  _NotaColumna(
    columna: 'nombre_articulo',
    obligatoria: 'si',
    valoresPermitidos: 'texto de 1 a 160 caracteres',
    descripcion:
        'Agrupa las filas del mismo producto. No puede repetirse en el archivo ni existir ya en el catálogo.',
  ),
  _NotaColumna(
    columna: 'tipo_venta',
    obligatoria: 'no',
    valoresPermitidos: 'unidad; fraccion',
    descripcion: 'Si se omite vale unidad.',
  ),
  _NotaColumna(
    columna: 'unidad_venta',
    obligatoria: 'condicional',
    valoresPermitidos: 'g; kg; ml; l',
    descripcion:
        'Obligatoria si tipo_venta es fraccion. Vacía si tipo_venta es unidad.',
  ),
  _NotaColumna(
    columna: 'nombre_variante',
    obligatoria: 'condicional',
    valoresPermitidos: 'texto de 1 a 160 caracteres',
    descripcion:
        'Obligatorio si el producto tiene más de una variante, y único dentro del producto.',
  ),
  _NotaColumna(
    columna: 'precio_venta',
    obligatoria: 'si',
    valoresPermitidos: 'decimal mayor que 0',
    descripcion:
        'Se redondea a centavos en el límite exacto, con redondeo half-up a dos decimales.',
  ),
  _NotaColumna(
    columna: 'precio_coste',
    obligatoria: 'no',
    valoresPermitidos: 'decimal mayor o igual que 0',
    descripcion: 'Vacío significa costo desconocido, no costo cero.',
  ),
  _NotaColumna(
    columna: 'seguimiento_existencias',
    obligatoria: 'no',
    valoresPermitidos: 'si; no',
    descripcion: 'Si se omite vale no.',
  ),
  _NotaColumna(
    columna: 'existencias',
    obligatoria: 'condicional',
    valoresPermitidos: 'decimal mayor o igual que 0',
    descripcion:
        'Obligatoria si seguimiento_existencias es si, y 0 es un valor válido.',
  ),
  _NotaColumna(
    columna: 'codigo_barras',
    obligatoria: 'no',
    valoresPermitidos: 'de 1 a 32 dígitos',
    descripcion: 'Solo números. Opcional.',
  ),
];
