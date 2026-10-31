import '../../../application/edicion_masiva/cambio_explicito.dart';
import '../../../domain/articulos/importe_comercial_codec.dart';
import 'dart:math' as math;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../application/import/articulo_catalog_import_service.dart';
import '../../../application/import/articulo_csv_contract.dart';
import '../../../application/import/articulo_import_solicitud.dart';
import '../../../application/import/articulo_import_actualizacion.dart';
import '../../../application/import/articulo_import_producto_error.dart';
import '../../../application/import/articulo_import_variante_cambio.dart';
import '../../../domain/articulos/nombre_variante.dart';
import '../../../domain/articulos/sale_mode.dart';
import '../../../domain/inventario/dimension_unidad.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/inventario/unidad_inventario.dart';
import 'csv_records_parser.dart';

/// Lee el contrato de columnas del catálogo y lo valida, sin escribir nada.
///
/// Es la mitad inversa de [ArticuloCsvContract]: el mismo contrato de columnas,
/// UTF-8 con BOM opcional y delimitador `,` o `;`. No hay SQL ni Drift: las
/// categorías, unidades y nombres existentes llegan resueltos en el catálogo.
///
/// Reglas que no se negocian aquí:
/// - el encabezado tiene que coincidir exactamente; una columna desconocida o
///   faltante es error, no se ignora (R2);
/// - diez columnas son altas; doce identifican ediciones; catorce agregan oferta;
/// - importes exactos con hasta dos decimales, sin redondeo silencioso (oferta v2).
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
  ArticuloImportSolicitud solicitarCatalogo(
    String contenido, {
    String? separador,
  }) {
    final archivo = _leerArchivo(contenido, separador: separador);
    if (archivo.errores.isNotEmpty) {
      return ArticuloImportSolicitud(
        errores: archivo.errores,
        delimitadorAmbiguo: archivo.ambiguo,
      );
    }
    return ArticuloImportSolicitud(
      productIds: Set.unmodifiable({
        if (archivo.conIds)
          for (final fila in archivo.filas)
            if (fila.isNotEmpty && fila[0].trim().isNotEmpty) fila[0].trim(),
      }),
      variantIds: Set.unmodifiable({
        if (archivo.conIds)
          for (final fila in archivo.filas)
            if (fila.length > 1 && fila[1].trim().isNotEmpty) fila[1].trim(),
      }),
    );
  }

  @override
  ArticuloImportReporte validar(
    String contenido, {
    required ArticuloImportCatalogo catalogo,
    String? separador,
  }) {
    final archivo = _leerArchivo(contenido, separador: separador);
    if (archivo.errores.isNotEmpty) {
      return ArticuloImportReporte(
        errores: archivo.errores,
        delimitadorAmbiguo: archivo.ambiguo,
      );
    }
    return _revisarFilas(archivo.filas, catalogo, conIds: archivo.conIds);
  }

  ({
    List<List<String>> filas,
    bool conIds,
    bool ambiguo,
    List<ArticuloImportError> errores,
  })
  _leerArchivo(String contenido, {String? separador}) {
    final candidatos =
        <
          ({
            String separador,
            List<List<String>> filas,
            int puntaje,
            String? error,
          })
        >[];
    for (final candidato in separador == null ? [',', ';'] : [separador]) {
      var puntajeEncabezado = -1;
      try {
        final primera = const CsvRecordsParser().parse(
          contenido,
          separator: candidato,
          maxRecords: 1,
        );
        final columnas = primera.isEmpty ? <String>[] : primera.first;
        puntajeEncabezado =
            columnas.where(ArticuloCsvContract.columnas.contains).length *
                1000 +
            (columnas.length > 1 ? 1 : 0);
        final filas = const CsvRecordsParser().parse(
          contenido,
          separator: candidato,
        );
        final encabezado = filas.isEmpty ? <String>[] : filas.first;
        // El contrato del encabezado tiene prioridad. Varias filas aportan
        // evidencia de estructura, pero nunca cambian el separador por fila.
        final consistentes = filas
            .skip(1)
            .take(20)
            .where(
              (fila) => fila.length == encabezado.length && fila.length > 1,
            )
            .length;
        candidatos.add((
          separador: candidato,
          filas: filas,
          puntaje: puntajeEncabezado + consistentes,
          error: null,
        ));
      } on FormatException catch (error) {
        candidatos.add((
          separador: candidato,
          filas: <List<String>>[],
          puntaje: puntajeEncabezado,
          error: error.message,
        ));
      }
    }
    candidatos.sort((a, b) => b.puntaje.compareTo(a.puntaje));
    final elegido = candidatos.first;
    final ambiguo =
        separador == null &&
        candidatos[0].puntaje == candidatos[1].puntaje &&
        contenido.trim().isNotEmpty;
    final filas = elegido.filas;
    final encabezado = filas.isEmpty ? <String>[] : filas.first;
    final conIds =
        encabezado.contains('product_id') || encabezado.contains('variant_id');
    final errores = <ArticuloImportError>[
      if (elegido.error != null)
        ArticuloImportError(columna: 'archivo', motivo: elegido.error!)
      else if (filas.isEmpty)
        const ArticuloImportError(
          columna: 'archivo',
          motivo: 'El archivo está vacío.',
        )
      else
        ..._revisarEncabezado(encabezado, conIds: conIds),
    ];
    if (ambiguo) {
      // El reporte conserva también los errores del encabezado. La elección
      // explícita nunca omite la revalidación del contrato completo.
      return (
        filas: [],
        conIds: conIds,
        ambiguo: true,
        errores: errores.isNotEmpty
            ? errores
            : [
                const ArticuloImportError(
                  columna: 'archivo',
                  motivo:
                      'No se pudo determinar el delimitador. Elige coma o punto y coma.',
                ),
              ],
      );
    }
    if (errores.isEmpty) {
      final cantidad = filas.length - 1;
      if (cantidad > maximoFilas) {
        errores.add(
          ArticuloImportError(
            columna: 'archivo',
            motivo:
                'El archivo tiene $cantidad filas y el máximo es $maximoFilas. Divídelo en varios archivos.',
          ),
        );
      }
      for (var i = 1; i < filas.length; i++) {
        if (filas[i].length != encabezado.length) {
          errores.add(
            ArticuloImportError(
              columna: 'archivo',
              motivo:
                  'El registro ${i + 1} tiene ${filas[i].length} campos y el encabezado declara ${encabezado.length}. '
                  'Usa el mismo delimitador "${elegido.separador}" en todo el archivo; '
                  'el encabezado y los datos no pueden usar delimitadores distintos. Revisa también las comillas.',
            ),
          );
        }
      }
    }
    return (
      filas: errores.isEmpty ? filas.skip(1).toList(growable: false) : [],
      conIds: conIds,
      ambiguo: false,
      errores: errores,
    );
  }

  /// El encabezado tiene que coincidir exactamente con el contrato (R2). Sin
  /// esto, un archivo viejo se rompería en silencio cuando cambien las columnas.
  static List<ArticuloImportError> _revisarEncabezado(
    List<String> encabezado, {
    required bool conIds,
  }) {
    final columnas = conIds
        ? (encabezado.contains('precio_oferta') ||
                  encabezado.contains('accion_oferta')
              ? ArticuloCsvContract.columnas
              : ArticuloCsvContract.columnasConIdsAnteriores)
        : ArticuloCsvContract.columnasAnteriores;
    final errores = <ArticuloImportError>[];
    for (final columna in columnas) {
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
      if (!columnas.contains(columna)) {
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
        encabezado.length == columnas.length &&
        List.generate(
          encabezado.length,
          (index) => encabezado[index] == columnas[index],
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
    List<List<String>> filas,
    ArticuloImportCatalogo catalogo, {
    required bool conIds,
  }) {
    final contexto = _Contexto(catalogo);
    final errores = <ArticuloImportError>[];
    final altas = <_Fila>[];
    final grupos = <String, List<_Fila>>{};
    final rechazados = <String>{};
    final variantesVistas = <String, String>{};
    final nombresActualizados = <String>{};

    for (var indice = 0; indice < filas.length; indice++) {
      final linea = indice + 2;
      final campos = filas[indice];
      final productId = conIds && campos.isNotEmpty ? campos[0].trim() : '';
      final variantId = conIds && campos.length > 1 ? campos[1].trim() : '';
      final existente = productId.isNotEmpty || variantId.isNotEmpty;
      final antes = errores.length;
      void error(String columna, String motivo) => errores.add(
        ArticuloImportError(linea: linea, columna: columna, motivo: motivo),
      );
      if (existente) {
        if (productId.isEmpty || variantId.isEmpty) {
          error(
            'product_id/variant_id',
            'Ambos IDs deben estar informados para actualizar.',
          );
        }
        final producto = catalogo.productosPorId[productId];
        final variante = catalogo.variantesPorId[variantId];
        if (productId.isNotEmpty && (producto == null || !producto.activo)) {
          error('product_id', 'El producto no existe o está inactivo.');
        }
        if (variantId.isNotEmpty && (variante == null || !variante.activa)) {
          error('variant_id', 'La variante no existe o está inactiva.');
        }
        if (producto != null &&
            variante != null &&
            variante.productId != productId) {
          error('variant_id', 'La variante no pertenece al producto indicado.');
        }
        if (variantId.isNotEmpty) {
          final anterior = variantesVistas[variantId];
          if (anterior != null) {
            error('variant_id', 'El variant_id está repetido en el archivo.');
            rechazados.add(anterior);
          } else {
            variantesVistas[variantId] = productId;
          }
        }
        if (campos.length > 3) nombresActualizados.add(_clave(campos[3]));
      }
      final fila = _revisarFila(
        conIds ? campos.sublist(2) : campos,
        linea,
        contexto,
        errores,
        existente: existente,
        variantId: existente ? variantId : null,
      );
      if (existente) {
        if (errores.length != antes) {
          rechazados.add(productId);
          // Solo excluye el propietario observado; nunca infiere una edición.
          final propietario = catalogo.variantesPorId[variantId]?.productId;
          if (propietario != null) rechazados.add(propietario);
        }
        if (fila != null) grupos.putIfAbsent(productId, () => []).add(fila);
      } else if (fila != null) {
        altas.add(fila);
      }
    }

    contexto.articulosExistentes.addAll(nombresActualizados);
    errores.addAll(_revisarNombres(altas, contexto));
    final nuevos = _agrupar(
      altas.where((f) => !f.rechazada).toList(),
      contexto,
      errores,
    );
    final cambiados = <ArticuloImportActualizacion>[];
    final iguales = <ArticuloImportActualizacion>[];
    for (final entry in grupos.entries) {
      if (rechazados.contains(entry.key)) continue;
      final actual = catalogo.productosPorId[entry.key]!;
      final grupo = entry.value;
      final primera = grupo.first;
      final inicio = errores.length;
      void error(_Fila fila, String columna, String motivo) => errores.add(
        ArticuloImportError(
          linea: fila.linea,
          columna: columna,
          motivo: motivo,
        ),
      );
      final propuestas = {for (final fila in grupo) fila.variantId!: fila};
      for (final fila in grupo) {
        if (fila.nombre != primera.nombre ||
            fila.categoriaId != primera.categoriaId ||
            fila.modoVenta != primera.modoVenta ||
            fila.unidadVenta?.id != primera.unidadVenta?.id) {
          error(
            fila,
            'producto',
            'Las filas del mismo product_id deben tener nombre, categoría y configuración comunes coherentes.',
          );
        }
        if (fila.modoVenta != actual.modoVenta ||
            fila.unidadVenta?.id != actual.unidadVentaId) {
          error(
            fila,
            'tipo_venta/unidad_venta',
            'El CSV no puede cambiar la configuración de venta.',
          );
        }
        if (fila.seguimiento !=
            catalogo.variantesPorId[fila.variantId]!.seguimientoExistencias) {
          error(
            fila,
            'seguimiento_existencias',
            'El CSV no puede cambiar el seguimiento de existencias.',
          );
        }
      }
      final activas = actual.variantes.where((v) => v.activa).toList();
      final nombres = <String>{};
      for (final variante in activas) {
        final fila = propuestas[variante.id];
        final nombre = NombreVariante.fromInput(
          fila == null ? variante.nombre : fila.nombreVariante,
        );
        if ((activas.length > 1 && nombre.value == null) ||
            (nombre.nameKey != null && !nombres.add(nombre.nameKey!))) {
          error(
            fila ?? primera,
            'nombre_variante',
            'Los nombres de todas las variantes del producto deben ser únicos y obligatorios si hay varias, incluidas las omitidas.',
          );
        }
      }
      for (final fila in grupo) {
        final v = catalogo.variantesPorId[fila.variantId]!;
        final offer = fila.offerPrice.establecer
            ? fila.offerPrice.valor
            : v.offerPriceMinor;
        if (offer != null && offer > fila.precioVentaMinor) {
          error(
            fila,
            'precio_oferta',
            'La oferta conservada supera el precio normal. Retírala o corrígela explícitamente.',
          );
        }
      }
      if (errores.length != inicio) continue;
      final propuesta = ArticuloImportActualizacion(
        actual: actual,
        nombre: primera.nombre,
        categoriaId: primera.categoriaId,
        variantes: List.unmodifiable([
          for (final fila in grupo)
            ArticuloImportVarianteCambio(
              id: fila.variantId!,
              linea: fila.linea,
              nombre: fila.nombreVariante,
              offerPrice: fila.offerPrice,
              precioVentaMinor: fila.precioVentaMinor,
              precioCosteMinor: fila.precioCosteMinor,
              codigoBarras: fila.codigoBarras,
            ),
        ]),
      );
      final cambia =
          unorm.nfkc(actual.nombre).trim() != primera.nombre ||
          actual.categoriaId != primera.categoriaId ||
          grupo.any((fila) {
            final v = catalogo.variantesPorId[fila.variantId]!;
            return NombreVariante.fromInput(v.nombre).value !=
                    fila.nombreVariante ||
                (fila.offerPrice.establecer &&
                    (!v.knowsOfferPrice ||
                        v.offerPriceMinor != fila.offerPrice.valor)) ||
                v.precioVentaMinor != fila.precioVentaMinor ||
                v.precioCosteMinor != fila.precioCosteMinor ||
                _opcional(v.codigoBarras) != fila.codigoBarras;
          });
      (cambia ? cambiados : iguales).add(propuesta);
    }
    final aceptadas = {
      for (final p in nuevos)
        for (final v in p.variantes) v.linea,
      for (final p in [...cambiados, ...iguales])
        for (final v in p.variantes) v.linea,
    };
    final excluidas = <String, List<int>>{};
    for (var i = 0; i < filas.length; i++) {
      if (aceptadas.contains(i + 2)) continue;
      final campos = filas[i];
      final id = conIds && campos.isNotEmpty ? campos[0].trim() : '';
      final nombreIndex = conIds ? 3 : 1;
      final nombre = campos.length > nombreIndex ? campos[nombreIndex] : '';
      final clave = id.isNotEmpty
          ? 'id:$id'
          : nombre.trim().isNotEmpty
          ? 'alta:${_clave(nombre)}'
          : 'linea:${i + 2}';
      excluidas.putIfAbsent(clave, () => []).add(i + 2);
    }
    return ArticuloImportReporte(
      productos: nuevos,
      productosConCambios: List.unmodifiable(cambiados),
      productosSinCambios: List.unmodifiable(iguales),
      errores: List.unmodifiable(errores),
      categorias: catalogo.categorias,
      productosConErrores: List.unmodifiable([
        for (final entry in excluidas.entries)
          ArticuloImportProductoError(
            productId: entry.key.startsWith('id:')
                ? entry.key.substring(3)
                : null,
            nombre: () {
              final campos = filas[entry.value.first - 2];
              final index = conIds ? 3 : 1;
              return campos.length > index && campos[index].trim().isNotEmpty
                  ? campos[index].trim()
                  : 'Sin nombre';
            }(),
            lineas: List.unmodifiable(entry.value),
          ),
      ]),
    );
  }

  static String? _opcional(String? valor) {
    final normalizado = unorm.nfkc(valor ?? '').trim();
    return normalizado.isEmpty ? null : normalizado;
  }

  /// Una fila del archivo ya normalizada. `rechazada` marca las filas cuyo
  /// fallo depende del grupo, que solo se puede saber cuando el grupo está
  /// completo: siguen en el grupo para que sus errores se reporten, pero no
  /// llegan al producto.
  _Fila? _revisarFila(
    List<String> campos,
    int linea,
    _Contexto contexto,
    List<ArticuloImportError> errores, {
    bool existente = false,
    String? variantId,
  }) {
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
      existente: existente,
    );
    final codigoBarras = _codigoBarras(campos[9], deFila);
    var offerPrice = const CambioExplicito<int?>.conservar();
    if (campos.length > 10) {
      try {
        final text = campos[10].trim();
        final action = campos[11].trim();
        if (action == 'retirar') {
          if (text.isNotEmpty) {
            throw const FormatException('Retirar exige precio_oferta vacío.');
          }
          offerPrice = const CambioExplicito.establecer(null);
        } else if (action == 'establecer' ||
            (action.isEmpty && text.isNotEmpty)) {
          offerPrice = CambioExplicito.establecer(
            const ImporteComercialCodec().parse(text, admiteCero: false),
          );
        } else if (action == 'conservar' || action.isEmpty) {
          if (text.isNotEmpty) {
            throw const FormatException('Conservar exige precio_oferta vacío.');
          }
        } else {
          throw const FormatException(
            'Acción de oferta inválida: conservar, establecer o retirar.',
          );
        }
        if (offerPrice.establecer &&
            offerPrice.valor != null &&
            precioVenta != null &&
            offerPrice.valor! > precioVenta) {
          throw const FormatException(
            'La oferta no puede superar el precio normal.',
          );
        }
      } on FormatException catch (e) {
        deFila.add(
          ArticuloImportError(
            columna: 'precio_oferta/accion_oferta',
            motivo: e.message,
          ),
        );
      }
    }

    if (deFila.isNotEmpty) {
      errores.addAll(deFila.map((error) => error.enLinea(linea)));
      return null;
    }
    return _Fila(
      variantId: variantId,
      linea: linea,
      nombre: nombre!,
      categoriaId: categoriaId,
      modoVenta: modoVenta!,
      unidadVenta: unidadVenta,
      nombreVariante: nombreVariante,
      offerPrice: offerPrice,
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

  /// Importes monetarios exactos; rechaza exceso de decimales en todos los formatos.
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
    try {
      return const ImporteComercialCodec().parse(
        normalizado,
        admiteCero: !obligatorio,
      );
    } on FormatException catch (e) {
      final text = e.message;
      errores.add(
        ArticuloImportError(
          columna: columna,
          motivo: normalizado.startsWith('-')
              ? (obligatorio
                    ? 'El precio de venta tiene que ser mayor que 0.'
                    : 'El precio de coste no puede ser negativo.')
              : text.contains('mayor que cero')
              ? 'El precio de venta tiene que ser mayor que 0.'
              : text.contains('hasta dos decimales')
              ? '"$normalizado" no es un importe válido. Usa hasta dos decimales.'
              : text,
        ),
      );
      return null;
    }
  }

  /// Auxiliar legado para validar magnitudes de existencias antes de su codec
  /// atómico. Los importes monetarios no usan esta conversión.
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
    UnidadInventario? unidadVenta, {
    bool existente = false,
  }) {
    final normalizado = valor.trim().replaceAll(',', '.');
    if (existente && normalizado.isEmpty) return 0;
    if (!existente && seguimiento != true) return 0;
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

  /// Para las altas, el nombre del artículo es la defensa contra
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
            offerPrice: fila.offerPrice,
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
    this.offerPrice = const CambioExplicito.conservar(),
    this.variantId,
  });

  final CambioExplicito<int?> offerPrice;
  final String? variantId;
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
