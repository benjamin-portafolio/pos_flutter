import 'dart:math' as math;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../application/import/articulo_catalog_import_service.dart';
import '../../../domain/articulos/sale_mode.dart';
import '../../../domain/inventario/dimension_unidad.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/inventario/unidad_inventario.dart';
import '../export/articulo_catalog_csv.dart';

/// Lee el contrato de columnas del catálogo y lo valida, sin escribir nada.
///
/// Es la mitad inversa de [ArticuloCatalogCsv]: el mismo contrato de columnas,
/// el mismo BOM y el mismo `,`. No hay SQL ni Drift, porque las categorías, las
/// unidades y los nombres que ya existen llegan resueltos en el catálogo.
///
/// Reglas que no se negocian aquí:
/// - el encabezado tiene que coincidir exactamente; una columna desconocida o
///   faltante es error, no se ignora (R2);
/// - el archivo nunca trae `product_id`, `variant_id`, `version` ni
///   `last_event_id`: la identidad se genera al procesar (D4);
/// - los importes se convierten a centavos una sola vez, en este límite, con
///   redondeo half-up a dos decimales (D7).
class ArticuloImportCsv implements ArticuloCatalogImportService {
  const ArticuloImportCsv();

  /// Tope del archivo (D9). 500 filas con seguimiento en todas emiten hasta 1000
  /// eventos, y ese es el límite que de verdad importa (H4).
  static const maximoFilas = 500;

  /// Un producto con más de una variante exige nombre en todas (D6). Sin eso el
  /// recurso de inventario de las variantes sin nombre se llama exactamente
  /// igual al producto (H1).
  static const maxLongitudNombre = 160;

  static final RegExp _decimal = RegExp(r'^(-)?(\d+)(?:\.(\d+))?$');
  static final RegExp _soloDigitos = RegExp(r'^[0-9]+$');

  /// Las únicas unidades con las que se puede vender por fracción (H8).
  static const unidadesDeFraccion = <String>{'g', 'kg', 'ml', 'l'};

  @override
  ArticuloImportReporte validar(
    String contenido, {
    required ArticuloImportCatalogo catalogo,
  }) {
    final lineas = _lineas(contenido);
    if (lineas.isEmpty) {
      return ArticuloImportReporte.rechazando(
        const ArticuloImportError(
          columna: 'archivo',
          motivo: 'El archivo está vacío.',
        ),
      );
    }

    final encabezado = _campos(lineas.first);
    final problemasEncabezado = _revisarEncabezado(encabezado);
    if (problemasEncabezado.isNotEmpty) {
      return ArticuloImportReporte(errores: problemasEncabezado);
    }

    final filas = lineas.skip(1).toList(growable: false);
    if (filas.length > maximoFilas) {
      return ArticuloImportReporte.rechazando(
        ArticuloImportError(
          columna: 'archivo',
          motivo:
              'El archivo tiene ${filas.length} filas y el máximo es '
              '$maximoFilas. Divídelo en varios archivos.',
        ),
      );
    }

    return _revisarFilas(filas, catalogo);
  }

  /// Líneas con datos, sin el BOM y sin las líneas en blanco. Las líneas en
  /// blanco se ignoran y no se interpretan como separadores (H17).
  static List<String> _lineas(String contenido) {
    final sinBom = contenido.startsWith(ArticuloCatalogCsv.bom)
        ? contenido.substring(ArticuloCatalogCsv.bom.length)
        : contenido;
    return sinBom
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((linea) => linea.trim().isNotEmpty)
        .toList(growable: false);
  }

  /// Parte una línea CSV respetando el entrecomillado que usa el compositor: un
  /// nombre de producto o de categoría puede contener `,` o `"` (H17, R12).
  static List<String> _campos(String linea) {
    final campos = <String>[];
    final buffer = StringBuffer();
    var entrecomillado = false;
    for (var index = 0; index < linea.length; index++) {
      final caracter = linea[index];
      if (entrecomillado) {
        if (caracter != '"') {
          buffer.write(caracter);
          continue;
        }
        if (index + 1 < linea.length && linea[index + 1] == '"') {
          buffer.write('"');
          index++;
          continue;
        }
        entrecomillado = false;
        continue;
      }
      if (caracter == '"') {
        entrecomillado = true;
        continue;
      }
      if (caracter == ArticuloCatalogCsv.separador) {
        campos.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(caracter);
    }
    campos.add(buffer.toString());
    return campos;
  }

  /// El encabezado tiene que coincidir exactamente con el contrato (R2). Sin
  /// esto, un archivo viejo se rompería en silencio cuando cambien las columnas.
  static List<ArticuloImportError> _revisarEncabezado(List<String> encabezado) {
    final errores = <ArticuloImportError>[];
    for (final columna in ArticuloCatalogCsv.columnas) {
      if (!encabezado.contains(columna)) {
        errores.add(
          ArticuloImportError(
            columna: columna,
            motivo: 'Falta la columna obligatoria "$columna" en el encabezado.',
          ),
        );
      }
    }
    // Si falta alguna columna obligatoria, el archivo no se puede interpretar y
    // reportar cada dato de la primera línea como columna desconocida solo
    // añade ruido: se dicen las columnas que faltan y se acaba.
    if (errores.isNotEmpty) return errores;

    for (final columna in encabezado) {
      if (!ArticuloCatalogCsv.columnas.contains(columna)) {
        errores.add(
          ArticuloImportError(
            columna: columna.isEmpty ? 'encabezado' : columna,
            motivo:
                'Columna desconocida "$columna". El archivo tiene que usar las '
                'columnas del catálogo, en el mismo orden.',
          ),
        );
      }
    }
    if (errores.isNotEmpty) return errores;

    // Mismo conjunto de columnas pero en otro orden: el compositor emite
    // siempre el mismo, así que un archivo reordenado no viene de esta app.
    final coincide =
        encabezado.length == ArticuloCatalogCsv.columnas.length &&
        List.generate(
          encabezado.length,
          (index) => encabezado[index] == ArticuloCatalogCsv.columnas[index],
        ).every((igual) => igual);
    if (!coincide) {
      errores.add(
        const ArticuloImportError(
          columna: 'encabezado',
          motivo:
              'El encabezado tiene que coincidir exactamente con el del '
              'catálogo, con las columnas en el mismo orden. Descarga la '
              'plantilla y vuelve a pegar los datos.',
        ),
      );
    }
    return errores;
  }

  ArticuloImportReporte _revisarFilas(
    List<String> filas,
    ArticuloImportCatalogo catalogo,
  ) {
    final contexto = _Contexto(catalogo);
    final errores = <ArticuloImportError>[];
    final aceptadas = <_Fila>[];

    for (var indice = 0; indice < filas.length; indice++) {
      final linea = indice + 2;
      final campos = _campos(filas[indice]);
      if (campos.length != ArticuloCatalogCsv.columnas.length) {
        errores.add(
          ArticuloImportError(
            linea: linea,
            columna: 'archivo',
            motivo:
                'La fila tiene ${campos.length} campos y el encabezado declara '
                '${ArticuloCatalogCsv.columnas.length}. Revisa que no falte un '
                '"," o que un texto no se haya partido.',
          ),
        );
        continue;
      }
      final fila = _revisarFila(campos, linea, contexto, errores);
      if (fila != null) aceptadas.add(fila);
    }

    errores.addAll(_revisarNombres(aceptadas, contexto));
    return ArticuloImportReporte(
      productos: _agrupar(
        aceptadas.where((fila) => !fila.rechazada).toList(growable: false),
        contexto,
        errores,
      ),
      errores: errores,
    );
  }

  /// Una fila del archivo ya normalizada. `rechazada` marca las filas cuyo
  /// fallo depende del grupo, que solo se puede saber cuando el grupo está
  /// completo: siguen en el grupo para que sus errores se reporten, pero no
  /// llegan al producto.
  _Fila? _revisarFila(
    List<String> campos,
    int linea,
    _Contexto contexto,
    List<ArticuloImportError> errores,
  ) {
    final deFila = <ArticuloImportError>[];

    final nombre = _nombreProducto(campos[1], deFila);
    final categoriaId = _categoria(campos[0], deFila, contexto);
    final modoVenta = _modoVenta(campos[2], deFila);
    final unidadVenta = _unidadVenta(campos[3], modoVenta, deFila, contexto);
    final nombreVariante = _nombreVariante(campos[4], deFila);
    final precioVenta = _precio(campos[5], deFila, obligatorio: true);
    final precioCoste = _precio(campos[6], deFila, obligatorio: false);
    final seguimiento = _seguimiento(campos[7], deFila);
    final existencias = _existencias(
      campos[8],
      seguimiento,
      deFila,
      contexto,
      modoVenta,
      unidadVenta,
    );
    final codigoBarras = _codigoBarras(campos[9], deFila);

    if (deFila.isNotEmpty) {
      errores.addAll(deFila.map((error) => error.enLinea(linea)));
      return null;
    }
    return _Fila(
      linea: linea,
      nombre: nombre!,
      categoriaId: categoriaId,
      modoVenta: modoVenta!,
      unidadVenta: unidadVenta,
      nombreVariante: nombreVariante,
      precioVentaMinor: precioVenta!,
      precioCosteMinor: precioCoste,
      seguimiento: seguimiento!,
      existenciasAtomic: existencias ?? 0,
      codigoBarras: codigoBarras,
    );
  }

  String? _nombreProducto(String valor, List<ArticuloImportError> errores) {
    final normalizado = unorm.nfkc(valor).trim();
    if (normalizado.isEmpty) {
      errores.add(
        const ArticuloImportError(
          columna: 'nombre_articulo',
          motivo: 'El nombre del artículo no puede estar vacío.',
        ),
      );
      return null;
    }
    if (normalizado.runes.length > maxLongitudNombre) {
      errores.add(
        ArticuloImportError(
          columna: 'nombre_articulo',
          motivo:
              'El nombre del artículo tiene ${normalizado.runes.length} '
              'caracteres y el máximo es $maxLongitudNombre.',
        ),
      );
      return null;
    }
    return normalizado;
  }

  String? _categoria(
    String valor,
    List<ArticuloImportError> errores,
    _Contexto contexto,
  ) {
    final normalizado = unorm.nfkc(valor).trim();
    if (normalizado.isEmpty) return null;
    final id = contexto.categoriasPorNombre[_clave(normalizado)];
    if (id == null) {
      errores.add(
        ArticuloImportError(
          columna: 'categoria',
          motivo:
              'La categoría "$normalizado" no existe. Las categorías no se '
              'crean al importar: créala antes y vuelve a intentarlo.',
        ),
      );
      return null;
    }
    return id;
  }

  SaleMode? _modoVenta(String valor, List<ArticuloImportError> errores) {
    final normalizado = valor.trim();
    if (normalizado.isEmpty) return SaleMode.unit;
    return switch (normalizado) {
      'unidad' => SaleMode.unit,
      'fraccion' => SaleMode.measured,
      _ => () {
        errores.add(
          ArticuloImportError(
            columna: 'tipo_venta',
            motivo:
                'El tipo de venta "$normalizado" no existe. Escribe "unidad" o '
                '"fraccion".',
          ),
        );
        return null;
      }(),
    };
  }

  UnidadInventario? _unidadVenta(
    String valor,
    SaleMode? modoVenta,
    List<ArticuloImportError> errores,
    _Contexto contexto,
  ) {
    final normalizado = valor.trim();
    if (normalizado.isEmpty) {
      if (modoVenta == SaleMode.measured) {
        errores.add(
          const ArticuloImportError(
            columna: 'unidad_venta',
            motivo:
                'La unidad de venta es obligatoria cuando el tipo de venta es '
                '"fraccion".',
          ),
        );
      }
      return null;
    }
    if (modoVenta == SaleMode.unit) {
      errores.add(
        ArticuloImportError(
          columna: 'unidad_venta',
          motivo:
              'La unidad de venta no se escribe cuando el tipo de venta es '
              '"unidad". Si el artículo se mide, pon "fraccion".',
        ),
      );
      return null;
    }
    // H8: `piece` no sirve para venta por fracción, así que el vocabulario son
    // cuatro códigos y no cinco. La comprobación es explícita y no una simple
    // búsqueda en el catálogo, porque `piece` sí está en el catálogo: es la
    // unidad del recurso en venta por unidad (H9), no una unidad de venta.
    if (!unidadesDeFraccion.contains(normalizado)) {
      errores.add(
        ArticuloImportError(
          columna: 'unidad_venta',
          motivo: normalizado == 'piece'
              ? 'La unidad de venta "piece" no sirve para venta por '
                    'fracción. Escribe g, kg, ml o l.'
              : 'La unidad de venta "$normalizado" no existe. Escribe g, '
                    'kg, ml o l.',
        ),
      );
      return null;
    }
    return contexto.unidadesPorCodigo[normalizado];
  }

  String? _nombreVariante(String valor, List<ArticuloImportError> errores) {
    final normalizado = unorm.nfkc(valor).trim();
    if (normalizado.isEmpty) return null;
    if (normalizado.runes.length > maxLongitudNombre) {
      errores.add(
        ArticuloImportError(
          columna: 'nombre_variante',
          motivo:
              'El nombre de la variante tiene ${normalizado.runes.length} '
              'caracteres y el máximo es $maxLongitudNombre.',
        ),
      );
      return null;
    }
    return normalizado;
  }

  /// Conversión a centavos una sola vez, en este límite (D7): el archivo guarda
  /// decimales y el redondeo es half-up a dos decimales, así que 18.005 entra
  /// como 18.01 y 18.004 como 18.00.
  int? _precio(
    String valor,
    List<ArticuloImportError> errores, {
    required bool obligatorio,
  }) {
    final columna = obligatorio ? 'precio_venta' : 'precio_coste';
    final normalizado = valor.trim().replaceAll(',', '.');
    if (normalizado.isEmpty) {
      if (!obligatorio) return null;
      errores.add(
        const ArticuloImportError(
          columna: 'precio_venta',
          motivo: 'El precio de venta es obligatorio.',
        ),
      );
      return null;
    }
    final centavosBig = _aCentavos(normalizado);
    if (centavosBig == null) {
      errores.add(
        ArticuloImportError(
          columna: columna,
          motivo: '"$normalizado" no es un importe válido.',
        ),
      );
      return null;
    }
    final centavos = centavosBig.toInt();
    final minimo = obligatorio ? 1 : 0;
    if (centavos < minimo) {
      errores.add(
        ArticuloImportError(
          columna: columna,
          motivo: obligatorio
              ? 'El precio de venta tiene que ser mayor que 0.'
              : 'El precio de coste no puede ser negativo.',
        ),
      );
      return null;
    }
    if (centavosBig > _maxImporte) {
      errores.add(
        ArticuloImportError(
          columna: columna,
          motivo: 'El importe excede el máximo permitido.',
        ),
      );
      return null;
    }
    return centavos;
  }

  static final BigInt _maxImporte = BigInt.from(9007199254740991);

  /// Decimal del archivo a centavos enteros, con redondeo half-up a dos
  /// decimales. Devuelve null cuando no es un número.
  static BigInt? _aCentavos(String entrada) {
    final coincidencia = _decimal.firstMatch(entrada);
    if (coincidencia == null) return null;
    final negativo = coincidencia.group(1) == '-';
    final entero = BigInt.parse(coincidencia.group(2)!);
    final decimales = coincidencia.group(3) ?? '';
    var centavos = BigInt.parse(
      decimales.substring(0, math.min(2, decimales.length)).padRight(2, '0'),
    );
    if (decimales.length > 2 && decimales.codeUnitAt(2) >= _cinco) {
      centavos += BigInt.one;
    }
    final magnitud = entero * BigInt.from(100) + centavos;
    return negativo ? -magnitud : magnitud;
  }

  /// Código de '5', el dígito que dispara el redondeo half-up.
  static const int _cinco = 0x35;

  bool? _seguimiento(String valor, List<ArticuloImportError> errores) {
    final normalizado = valor.trim();
    if (normalizado.isEmpty) return false;
    return switch (normalizado) {
      'si' => true,
      'no' => false,
      _ => () {
        errores.add(
          ArticuloImportError(
            columna: 'seguimiento_existencias',
            motivo:
                '"$normalizado" no es un valor válido. Escribe "si" o "no".',
          ),
        );
        return null;
      }(),
    };
  }

  /// `existencias` es obligatoria con seguimiento `si` y `0` es un valor
  /// válido: vacío significa "no lo sé", no cero (R4).
  int? _existencias(
    String valor,
    bool? seguimiento,
    List<ArticuloImportError> errores,
    _Contexto contexto,
    SaleMode? modoVenta,
    UnidadInventario? unidadVenta,
  ) {
    final normalizado = valor.trim().replaceAll(',', '.');
    if (seguimiento != true) return 0;
    if (normalizado.isEmpty) {
      errores.add(
        const ArticuloImportError(
          columna: 'existencias',
          motivo:
              'Las existencias son obligatorias con seguimiento de '
              'existencias. Si el artículo no tiene saldo, escribe 0.',
        ),
      );
      return null;
    }
    final magnitud = _aCentavos(normalizado);
    if (magnitud == null || magnitud.isNegative) {
      errores.add(
        ArticuloImportError(
          columna: 'existencias',
          motivo: '"$normalizado" no es una cantidad válida.',
        ),
      );
      return null;
    }
    final unidad = contexto.unidadInventario(modoVenta, unidadVenta);
    if (unidad == null) {
      errores.add(
        const ArticuloImportError(
          columna: 'existencias',
          motivo:
              'Este dispositivo no tiene la unidad de inventario que necesita '
              'esta fila, así que no puede abrir el seguimiento de existencias.',
        ),
      );
      return null;
    }
    try {
      return const InventoryQuantityCodec().parseNonNegativeAtomic(
        normalizado,
        unidad,
      );
    } on FormatException catch (error) {
      errores.add(
        ArticuloImportError(columna: 'existencias', motivo: error.message),
      );
      return null;
    }
  }

  String? _codigoBarras(String valor, List<ArticuloImportError> errores) {
    final normalizado = unorm.nfkc(valor).trim();
    if (normalizado.isEmpty) return null;
    if (!_soloDigitos.hasMatch(normalizado) || normalizado.length > 32) {
      errores.add(
        ArticuloImportError(
          columna: 'codigo_barras',
          motivo:
              'El código de barras "$normalizado" solo admite dígitos, hasta '
              '32.',
        ),
      );
      return null;
    }
    return normalizado;
  }

  /// Sin columna de identidad, el nombre del artículo es la única defensa contra
  /// dos productos distintos con el mismo nombre (R5). Repetir el mismo nombre
  /// es la forma de agrupar variantes, así que el rechazo es cuando dos
  /// escrituras distintas normalizan al mismo nombre: se fusionarían en un solo
  /// producto sin que nadie lo pidiera.
  ///
  /// Las filas rechazadas aquí no llegan al producto, porque un artículo que ya
  /// existe en el catálogo no se vuelve a dar de alta.
  static List<ArticuloImportError> _revisarNombres(
    List<_Fila> filas,
    _Contexto contexto,
  ) {
    final propias = <ArticuloImportError>[];
    final escrituraPorClave = <String, String>{};
    for (final fila in filas) {
      final clave = _clave(fila.nombre);
      final anterior = escrituraPorClave[clave];
      if (anterior == null) {
        escrituraPorClave[clave] = fila.nombre;
      } else if (anterior != fila.nombre) {
        propias.add(
          ArticuloImportError(
            linea: fila.linea,
            columna: 'nombre_articulo',
            motivo:
                '"${fila.nombre}" es el mismo artículo que "$anterior". '
                'Escribe el nombre igual en todas sus filas para que se agrupen.',
          ),
        );
        fila.rechazada = true;
      }
      if (contexto.articulosExistentes.contains(clave)) {
        propias.add(
          ArticuloImportError(
            linea: fila.linea,
            columna: 'nombre_articulo',
            motivo: 'Ya existe un producto llamado "${fila.nombre}".',
          ),
        );
        fila.rechazada = true;
      }
    }
    return propias;
  }

  /// Agrupación por `nombre_articulo` con `sort_order` desde cero, en el orden
  /// de fila. Un producto con más de una variante exige nombre en todas (D6) y
  /// el nombre no se repite dentro del producto (H10).
  static List<ArticuloImportProducto> _agrupar(
    List<_Fila> filas,
    _Contexto contexto,
    List<ArticuloImportError> errores,
  ) {
    final grupos = <String, List<_Fila>>{};
    for (final fila in filas) {
      grupos.putIfAbsent(_clave(fila.nombre), () => <_Fila>[]).add(fila);
    }

    final productos = <ArticuloImportProducto>[];
    for (final grupo in grupos.values) {
      // Con más de una fila el producto tiene más de una variante, así que
      // todas necesitan nombre: si no, dos variantes sin nombre comparten
      // exactamente el mismo nombre de recurso (H1, D6).
      final requiereNombre = grupo.length > 1;

      final variantes = <ArticuloImportVariante>[];
      // La primera fila con un nombre de variante gana; las siguientes que
      // repiten ese nombre se rechazan. Así el error se reporta una sola vez, en
      // la fila sobrante, y el producto conserva la variante original.
      final variantesVistas = <String>{};
      for (final fila in grupo) {
        if (requiereNombre && fila.nombreVariante == null) {
          errores.add(
            ArticuloImportError(
              linea: fila.linea,
              columna: 'nombre_variante',
              motivo:
                  'El artículo "${fila.nombre}" tiene más de una variante, así '
                  'que todas necesitan nombre en "nombre_variante".',
            ),
          );
          continue;
        }
        if (fila.nombreVariante != null &&
            !variantesVistas.add(_clave(fila.nombreVariante!))) {
          errores.add(
            ArticuloImportError(
              linea: fila.linea,
              columna: 'nombre_variante',
              motivo:
                  'La variante "${fila.nombreVariante}" está repetida en el '
                  'artículo "${fila.nombre}".',
            ),
          );
          continue;
        }
        variantes.add(
          ArticuloImportVariante(
            linea: fila.linea,
            sortOrder: variantes.length,
            nombre: fila.nombreVariante,
            precioVentaMinor: fila.precioVentaMinor,
            precioCosteMinor: fila.precioCosteMinor,
            codigoBarras: fila.codigoBarras,
            seguimientoExistencias: fila.seguimiento,
            existenciasAtomic: fila.existenciasAtomic,
          ),
        );
      }

      if (variantes.isEmpty) continue;
      final primera = grupo.first;
      final unidadInventario = contexto.unidadInventario(
        primera.modoVenta,
        primera.unidadVenta,
      );
      productos.add(
        ArticuloImportProducto(
          nombre: primera.nombre,
          categoriaId: primera.categoriaId,
          modoVenta: primera.modoVenta,
          unidadVentaId: primera.unidadVenta?.id,
          cantidadReferenciaPrecioAtomic: primera.unidadVenta?.factorAtomico,
          unidadInventarioId: unidadInventario?.id,
          variantes: List.unmodifiable(variantes),
        ),
      );
    }
    return List.unmodifiable(productos);
  }
}

/// Clave de comparación: NFKC, sin espacios sobrantes y sin mayúsculas. Es la
/// misma normalización que aplica el dominio a los nombres, para que el archivo
/// no pueda crear dos productos que la app vería como uno.
String _clave(String valor) => unorm.nfkc(valor).trim().toLowerCase();

/// Índice del catálogo para la validación, construido una vez por archivo.
class _Contexto {
  _Contexto(ArticuloImportCatalogo catalogo)
    : categoriasPorNombre = {
        for (final categoria in catalogo.categorias)
          _clave(categoria.nombre): categoria.id,
      },
      unidadesPorCodigo = {
        for (final unidad in catalogo.unidades) unidad.code: unidad,
      },
      articulosExistentes = {
        for (final nombre in catalogo.nombresArticulos) _clave(nombre),
      };

  final Map<String, String> categoriasPorNombre;
  final Map<String, UnidadInventario> unidadesPorCodigo;
  final Set<String> articulosExistentes;

  /// La unidad del recurso sale de la forma de venta (H9): `piece` si se vende
  /// por unidad, la misma unidad de venta si se vende por fracción.
  ///
  /// En venta por unidad no hay unidad de venta que tomar, así que la pieza se
  /// busca por dimensión y factor atómico, no por código.
  UnidadInventario? unidadInventario(
    SaleMode? modoVenta,
    UnidadInventario? unidadVenta,
  ) {
    if (modoVenta == null) return null;
    if (modoVenta == SaleMode.measured) return unidadVenta;
    for (final unidad in unidadesPorCodigo.values) {
      if (unidad.dimension == DimensionUnidad.count &&
          unidad.factorAtomico == 1) {
        return unidad;
      }
    }
    return null;
  }
}

/// Fila del archivo ya normalizada. [rechazada] la marca el agrupador cuando el
/// fallo depende del grupo entero.
class _Fila {
  _Fila({
    required this.linea,
    required this.nombre,
    required this.modoVenta,
    required this.precioVentaMinor,
    required this.seguimiento,
    required this.existenciasAtomic,
    this.categoriaId,
    this.unidadVenta,
    this.nombreVariante,
    this.precioCosteMinor,
    this.codigoBarras,
  });

  final int linea;
  final String nombre;
  final String? categoriaId;
  final SaleMode modoVenta;
  final UnidadInventario? unidadVenta;
  final String? nombreVariante;
  final int precioVentaMinor;
  final int? precioCosteMinor;
  final bool seguimiento;
  final int existenciasAtomic;
  final String? codigoBarras;
  bool rechazada = false;
}
