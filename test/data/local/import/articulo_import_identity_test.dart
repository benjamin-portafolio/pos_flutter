import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/import/articulo_csv_contract.dart';
import 'package:pos_flutter/application/import/articulo_import_producto_local.dart';
import 'package:pos_flutter/application/import/articulo_import_variante_local.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/domain/articulos/sale_mode.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';

const _parser = ArticuloImportCsv();
const _unidades = [
  UnidadInventario(
    id: 'piece',
    code: 'piece',
    nombre: 'Pieza',
    simbolo: 'pza',
    dimension: DimensionUnidad.count,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  ),
  UnidadInventario(
    id: 'kg',
    code: 'kg',
    nombre: 'Kilogramo',
    simbolo: 'kg',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  ),
];
ArticuloImportVarianteLocal _variante(
  String id, {
  String productId = 'P',
  String? nombre,
  bool activa = true,
  bool seguimiento = false,
  int orden = 0,
  int? oferta,
  bool conoceOferta = true,
}) => ArticuloImportVarianteLocal(
  id: id,
  productId: productId,
  activa: activa,
  sortOrder: orden,
  nombre: nombre,
  precioVentaMinor: 2500,
  offerPriceMinor: oferta,
  knowsOfferPrice: conoceOferta,
  precioCosteMinor: 1000,
  codigoBarras: '00123',
  seguimientoExistencias: seguimiento,
);
ArticuloImportProductoLocal _producto({
  String id = 'P',
  String nombre = 'Café',
  bool activo = true,
  bool medido = false,
  List<ArticuloImportVarianteLocal>? variantes,
}) => ArticuloImportProductoLocal(
  id: id,
  activo: activo,
  nombre: nombre,
  categoriaId: 'cat',
  modoVenta: medido ? SaleMode.measured : SaleMode.unit,
  unidadVentaId: medido ? 'kg' : null,
  cantidadReferenciaPrecioAtomic: medido ? 250 : null,
  lastEventId: 'base-$id',
  variantes: variantes ?? [_variante('V', productId: id)],
);
ArticuloImportCatalogo _catalogo(List<ArticuloImportProductoLocal> productos) =>
    ArticuloImportCatalogo(
      unidades: _unidades,
      categorias: const [ArticuloImportCategoria(id: 'cat', nombre: 'Bebidas')],
      nombresArticulos: {
        for (final p in productos)
          if (p.activo) p.nombre,
      },
      productosPorId: {for (final p in productos) p.id: p},
      variantesPorId: {
        for (final p in productos)
          for (final v in p.variantes) v.id: v,
      },
    );
String _fila({
  String p = 'P',
  String v = 'V',
  String nombre = 'Café',
  String categoria = 'Bebidas',
  String tipo = 'unidad',
  String unidad = '',
  String variante = '',
  String precio = '25',
  String costo = '10',
  String barcode = '00123',
  String tracking = 'no',
  String stock = '',
}) => [
  p,
  v,
  categoria,
  nombre,
  tipo,
  unidad,
  variante,
  precio,
  costo,
  tracking,
  stock,
  barcode,
].join(',');
String _archivo(List<String> filas) =>
    '${ArticuloCsvContract.columnasConIdsAnteriores.join(',')}\n${filas.join('\n')}\n';
ArticuloImportReporte _validar(
  List<String> filas, {
  List<ArticuloImportProductoLocal>? productos,
}) => _parser.validar(
  _archivo(filas),
  catalogo: _catalogo(productos ?? [_producto()]),
);

void main() {
  _nuevoFormatoTests();
  test('C01-C03 dos formatos explícitos; altas sin IDs no generan identidad', () {
    final nuevo = _validar([_fila(p: '', v: '', nombre: 'Nuevo')]);
    expect(nuevo.errores, isEmpty);
    expect(nuevo.productos.single.nombre, 'Nuevo');
    expect(nuevo.productosConCambios, isEmpty);
    final anterior =
        '${ArticuloCsvContract.columnasAnteriores.join(',')}\nBebidas,Café,unidad,,,25,10,no,0,00123\n';
    final legado = _parser.validar(
      anterior,
      catalogo: _catalogo([_producto()]),
    );
    expect(legado.productos, isEmpty);
    expect(legado.errores.single.motivo, contains('Ya existe'));
  });
  test('C04 C16 C21 normalización visible, centavos y saldo informativo', () {
    for (final precio in ['25', '25.0', '25.00']) {
      final r = _validar([
        _fila(
          nombre: '  Ｃafé  ',
          precio: precio,
          stock: '999',
          barcode: '００１２３',
        ),
      ]);
      expect(r.errores, isEmpty);
      expect(r.productosSinCambios.single.productId, 'P');
      expect(r.filasSinCambios, 1);
      expect(r.importable, isFalse);
      expect(r.productos, isEmpty);
    }
  });
  test('C05-C06 C17 precio, costo, barcode y nombres visibles son cambios', () {
    for (final fila in [
      _fila(precio: '26'),
      _fila(costo: '0'),
      _fila(barcode: '00001'),
      _fila(nombre: 'CAFÉ'),
      _fila(variante: 'Especial'),
    ]) {
      final r = _validar([fila]);
      expect(r.errores, isEmpty);
      expect(r.productosConCambios.single.baseEventId, 'base-P');
      expect(r.productos, isEmpty);
      expect(r.filasConCambios, 1);
    }
  });
  test('C07 IDs incompletos son errores y excluyen el producto completo', () {
    for (final fila in [_fila(v: ''), _fila(p: '')]) {
      final r = _validar([_fila(precio: '26'), fila]);
      expect(r.errores, isNotEmpty);
      expect(r.productosConCambios, isEmpty);
      expect(r.productosSinCambios, isEmpty);
      expect(r.productos, isEmpty);
    }
  });
  test('C08 IDs opacos, desconocidos e inactivos nunca son altas', () {
    for (final r in [
      _validar([_fila(p: 'p')]),
      _validar([_fila(v: 'v')]),
      _validar([_fila()], productos: [_producto(activo: false)]),
      _validar(
        [_fila()],
        productos: [
          _producto(variantes: [_variante('V', activa: false)]),
        ],
      ),
    ]) {
      expect(r.errores, isNotEmpty);
      expect(r.productos, isEmpty);
      expect(r.productosConCambios, isEmpty);
    }
    expect(
      _validar([_fila(p: ' P ', v: ' V ')]).productosSinCambios,
      hasLength(1),
    );
  });
  test('C09 pertenencia incorrecta no se resuelve por nombre ni barcode', () {
    final r = _validar(
      [_fila(v: 'W')],
      productos: [
        _producto(),
        _producto(
          id: 'Q',
          variantes: [_variante('W', productId: 'Q')],
        ),
      ],
    );
    expect(r.errores.single.motivo, contains('no pertenece'));
    expect(r.productosConCambios, isEmpty);
  });
  test(
    'C10 duplicados iguales, diferentes e inválidos excluyen ambos grupos',
    () {
      for (final segunda in [
        _fila(),
        _fila(precio: '27'),
        _fila(precio: 'error'),
      ]) {
        final r = _validar([_fila(), segunda]);
        expect(r.errores.map((e) => e.columna), contains('variant_id'));
        expect(r.productosSinCambios, isEmpty);
        expect(r.productosConCambios, isEmpty);
      }
    },
  );
  test(
    'C11 contradicciones de campos comunes excluyen el agregado completo',
    () {
      final p = _producto(
        variantes: [
          _variante('V', nombre: 'Chica'),
          _variante('W', nombre: 'Grande', orden: 1),
        ],
      );
      for (final fila in [
        _fila(v: 'W', variante: 'Grande', nombre: 'Otro'),
        _fila(v: 'W', variante: 'Grande', categoria: ''),
        _fila(v: 'W', variante: 'Grande', tipo: 'fraccion', unidad: 'kg'),
      ]) {
        final r = _validar([_fila(variante: 'Chica'), fila], productos: [p]);
        expect(r.errores, isNotEmpty);
        expect(r.productosConCambios, isEmpty);
        expect(r.productosSinCambios, isEmpty);
      }
    },
  );
  test('C12 C25 dos IDs con mismo nombre/barcode no se fusionan', () {
    final r = _validar(
      [_fila(precio: '26'), _fila(p: 'Q', v: 'W', precio: '27')],
      productos: [
        _producto(),
        _producto(
          id: 'Q',
          variantes: [_variante('W', productId: 'Q')],
        ),
      ],
    );
    expect(r.errores, isEmpty);
    expect(r.productosConCambios.map((p) => p.productId), ['P', 'Q']);
  });
  test('C13-C15 variantes omitidas y orden local se conservan al revisar', () {
    final p = _producto(
      variantes: [
        _variante('V', nombre: 'Chica'),
        _variante('W', nombre: 'Grande', orden: 1),
        _variante('X', nombre: 'Mediana', orden: 2),
      ],
    );
    final r = _validar(
      [
        _fila(v: 'W', variante: 'Grande', precio: '26'),
        _fila(variante: 'Chica'),
      ],
      productos: [p],
    );
    expect(r.errores, isEmpty);
    final cambio = r.productosConCambios.single;
    expect(identical(cambio.actual, p), isTrue);
    expect(cambio.actual.variantes.map((v) => v.id), ['V', 'W', 'X']);
    expect(cambio.actual.variantes.map((v) => v.sortOrder), [0, 1, 2]);
    expect(cambio.variantes.map((v) => v.id), ['W', 'V']);
    final colision = _validar([_fila(variante: ' GRANDE ')], productos: [p]);
    expect(colision.errores.single.columna, 'nombre_variante');
    expect(colision.productosConCambios, isEmpty);
    expect(
      _validar([_fila()], productos: [p]).errores.single.columna,
      'nombre_variante',
    );
  });
  test(
    'C18 vacíos retiran categoría/barcode y vuelven el costo desconocido',
    () {
      final cambio = _validar([
        _fila(categoria: '', costo: '', barcode: ''),
      ]).productosConCambios.single;
      expect(cambio.categoriaId, isNull);
      expect(cambio.variantes.single.precioCosteMinor, isNull);
      expect(cambio.variantes.single.codigoBarras, isNull);
    },
  );
  test('C19 configuración y seguimiento no se pueden cambiar', () {
    for (final fila in [
      _fila(tipo: 'fraccion', unidad: 'kg'),
      _fila(tracking: 'si', stock: '1'),
    ]) {
      final r = _validar([fila]);
      expect(r.errores, isNotEmpty);
      expect(r.productosConCambios, isEmpty);
    }
    final medido = _producto(medido: true);
    expect(
      _validar([_fila(tipo: 'unidad')], productos: [medido]).errores,
      isNotEmpty,
    );
  });
  test(
    'C20-C22 referencia exacta conservada; saldo vacío, distinto e inválido',
    () {
      final p = _producto(
        medido: true,
        variantes: [_variante('V', seguimiento: true)],
      );
      for (final stock in ['', '25.123']) {
        final r = _validar(
          [_fila(tipo: 'fraccion', unidad: 'kg', tracking: 'si', stock: stock)],
          productos: [p],
        );
        expect(r.errores, isEmpty);
        expect(
          r.productosSinCambios.single.actual.cantidadReferenciaPrecioAtomic,
          250,
        );
      }
      for (final stock in ['mucho', '-1', '1.0001']) {
        final r = _validar(
          [_fila(tipo: 'fraccion', unidad: 'kg', tracking: 'si', stock: stock)],
          productos: [p],
        );
        expect(r.errores.single.columna, 'existencias');
        expect(r.productosConCambios, isEmpty);
      }
      expect(
        _validar([_fila(stock: 'inválida')]).errores.single.columna,
        'existencias',
      );
    },
  );
  test(
    'C26 error de negocio excluye producto; estructura inválida bloquea archivo',
    () {
      final p = _producto(
        variantes: [
          _variante('V', nombre: 'Chica'),
          _variante('W', nombre: 'Grande', orden: 1),
        ],
      );
      for (final fila in [
        _fila(v: 'W', variante: 'Grande', precio: 'error'),
        'P,W,menos campos',
      ]) {
        final r = _validar(
          [
            _fila(variante: 'Chica', precio: '26'),
            fila,
            _fila(p: '', v: '', nombre: 'Nuevo'),
          ],
          productos: [p],
        );
        expect(r.productosConCambios, isEmpty);
        if (fila == 'P,W,menos campos') {
          expect(r.productos, isEmpty);
          expect(r.erroresEstructurales, isTrue);
          expect(r.importable, isFalse);
        } else {
          expect(r.productos.single.nombre, 'Nuevo');
        }
        expect(r.errores, isNotEmpty);
      }
    },
  );
  test('C27 alta con nombre de actualización no se fusiona ni se ejecuta', () {
    for (final nombre in ['Café', 'Renombrado']) {
      final r = _validar([
        _fila(nombre: 'Renombrado'),
        _fila(p: '', v: '', nombre: nombre),
      ]);
      expect(r.productos, isEmpty);
      expect(r.productosConCambios, hasLength(1));
      expect(r.errores.single.motivo, contains('Ya existe'));
    }
  });
  test(
    'C28 encabezados estrictos para doce columnas y límite incluye omitidos',
    () {
      final columnas = ArticuloCsvContract.columnas;
      for (final header in [
        columnas.reversed.join(','),
        '${columnas.join(',')},extra',
        columnas.skip(1).join(','),
        '${columnas.join(',')},product_id',
      ]) {
        final r = _parser.validar(
          '$header\n${_fila()}\n',
          catalogo: _catalogo([_producto()]),
        );
        expect(r.erroresEstructurales, isTrue);
        expect(r.productosSinCambios, isEmpty);
      }
      final r = _validar(List.generate(501, (_) => _fila()));
      expect(r.erroresEstructurales, isTrue);
      expect(r.errores.single.motivo, contains('501 filas'));
    },
  );
  test('solicitud pura conserva IDs recortados y no lee catálogo', () {
    final s = _parser.solicitarCatalogo(
      '\uFEFF${_archivo([_fila(p: ' P ', v: ' V '), _fila(p: '', v: '', nombre: 'Nuevo')])}',
    );
    expect(s.errores, isEmpty);
    expect(s.productIds, {'P'});
    expect(s.variantIds, {'V'});
  });
  test(
    'contrato público admite altas e identidad sin bandera de activación',
    () {
      const publico = ArticuloImportCsv();
      for (final fila in [_fila(), _fila(p: '', v: '', nombre: 'Nuevo')]) {
        final reporte = publico.validar(
          _archivo([fila]),
          catalogo: _catalogo([_producto()]),
        );
        expect(reporte.errores, isEmpty);
        expect(reporte.filasValidas, 1);
      }
    },
  );
}

void _nuevoFormatoTests() {
  ArticuloImportReporte revisar(
    List<String> filas, {
    int? oferta = 2000,
    bool conocida = true,
    List<String> columnas = ArticuloCsvContract.columnas,
    List<ArticuloImportProductoLocal>? productos,
  }) => _parser.validar(
    '${columnas.join(',')}\n${filas.join('\n')}\n',
    catalogo: _catalogo(
      productos ??
          [
            _producto(
              variantes: [
                _variante('V', oferta: oferta, conoceOferta: conocida),
              ],
            ),
          ],
    ),
  );
  test('nuevo precio_oferta: igual, cambiado, vacío y sin oferta conocida', () {
    expect(revisar(['${_fila()},20,']).productosSinCambios, hasLength(1));
    expect(
      revisar([
        '${_fila()},19.50,',
      ]).productosConCambios.single.variantes.single.offerPrice.valor,
      1950,
    );
    expect(
      revisar([
        '${_fila()},,',
      ]).productosConCambios.single.variantes.single.offerPrice.valor,
      isNull,
    );
    for (final conocida in [true, false]) {
      expect(
        revisar(
          ['${_fila()},,'],
          oferta: null,
          conocida: conocida,
        ).productosSinCambios,
        hasLength(1),
      );
    }
    for (final precio in ['0', '-1', '26', '1.234', 'abc']) {
      expect(revisar(['${_fila()},$precio,']).errores, isNotEmpty);
    }
  });
  test(
    'sin columnas de oferta conserva; accion_oferta conserva contrato legado',
    () {
      final ausente = revisar([
        _fila(),
      ], columnas: ArticuloCsvContract.columnasConIdsAnteriores);
      expect(
        ausente
            .productosSinCambios
            .single
            .variantes
            .single
            .offerPrice
            .establecer,
        isFalse,
      );
      for (final oferta in ['', ',conservar']) {
        final celda = oferta.isEmpty ? ',' : oferta;
        final legado = revisar([
          '${_fila()},$celda',
        ], columnas: ArticuloCsvContract.columnasConOfertaAnteriores);
        expect(legado.productosSinCambios, hasLength(1));
      }
      expect(
        revisar(
          ['${_fila()},,retirar'],
          columnas: ArticuloCsvContract.columnasConOfertaAnteriores,
        ).productosConCambios.single.variantes.single.offerPrice.valor,
        isNull,
      );
      expect(
        revisar(
          ['${_fila()},19,establecer'],
          columnas: ArticuloCsvContract.columnasConOfertaAnteriores,
        ).productosConCambios.single.variantes.single.offerPrice.valor,
        1900,
      );
      expect(
        revisar([
          '${_fila()},20,retirar',
        ], columnas: ArticuloCsvContract.columnasConOfertaAnteriores).errores,
        isNotEmpty,
      );
    },
  );
  test('alta nueva con precio_oferta vacío crea sin oferta', () {
    final r = revisar(['${_fila(p: '', v: '', nombre: 'Nuevo')},,']);
    expect(r.errores, isEmpty);
    expect(r.productos.single.variantes.single.offerPrice.valor, isNull);
  });
  test(
    'eliminación completa con campos comerciales vacíos e IDs normalizados',
    () {
      final p = _producto(
        variantes: [
          _variante('V', nombre: 'Chica', oferta: 2000),
          _variante('W', nombre: 'Grande', oferta: 2000),
        ],
      );
      final r = revisar(
        [
          [' P ', '', ...List.filled(11, ''), ' SI '].join(','),
          '${_fila(v: 'W', variante: 'Grande')},20,',
        ],
        productos: [p],
      );
      expect(r.errores, isEmpty);
      expect(r.eliminaciones.single.actual.variantes, hasLength(2));
      expect(r.eliminaciones.single.lineas, [2, 3]);
      expect(r.productosConCambios, isEmpty);
      expect(r.productosSinCambios, isEmpty);
      expect(r.importable, isTrue);
      final dos = revisar(['${_fila()},,si', '${_fila(v: '')},,si']);
      expect(dos.errores, isEmpty);
      expect(dos.eliminaciones, hasLength(1));
      // La fila de eliminación ignora incluso datos comerciales inválidos.
      expect(revisar(['${_fila(precio: 'abc')},inválido,si']).errores, isEmpty);
    },
  );
  test('eliminación: IDs inválidos, pertenencia y acciones desconocidas', () {
    for (final fila in [
      '${_fila(p: '', v: '')},,si',
      '${_fila(p: 'desconocido')},,si',
      '${_fila(v: 'desconocida')},,si',
      '${_fila()},,quizás',
    ]) {
      final r = revisar([fila]);
      expect(r.errores, isNotEmpty);
      expect(r.eliminaciones, isEmpty);
      expect(r.importable, isFalse);
    }
    final p = _producto();
    final q = _producto(
      id: 'Q',
      variantes: [_variante('W', productId: 'Q')],
    );
    expect(
      revisar(['${_fila(v: 'W')},,si'], productos: [p, q]).eliminaciones,
      isEmpty,
    );
    expect(
      revisar(
        ['${_fila()},,si'],
        productos: [_producto(activo: false)],
      ).eliminaciones,
      isEmpty,
    );
    expect(revisar(['${_fila()},20, NO ']).productosSinCambios, hasLength(1));
  });
  test(
    'rechaza eliminación con cambios comerciales, oferta real o variante nueva',
    () {
      final p = _producto(
        variantes: [
          _variante('V', nombre: 'Chica', oferta: 2000),
          _variante('W', nombre: 'Grande', oferta: 2000),
        ],
      );
      for (final otra in [
        '${_fila(v: 'W', variante: 'Grande', precio: '26')},20,',
        '${_fila(v: 'W', variante: 'Grande')},19,',
        '${_fila(v: 'W', variante: 'Grande')},,',
        '${_fila(v: '', variante: 'Nueva')},,',
        '${_fila(v: 'W', variante: 'Grande', precio: 'inválido')},20,',
      ]) {
        final r = revisar(
          ['${_fila(variante: 'Chica')},,si', otra],
          productos: [p],
        );
        expect(r.errores, isNotEmpty);
        expect(r.eliminaciones, isEmpty);
        expect(r.productosConCambios, isEmpty);
        expect(r.productos, isEmpty);
      }
    },
  );
  test('encabezados híbridos o incompletos se rechazan explícitamente', () {
    for (final columnas in [
      [...ArticuloCsvContract.columnas, 'accion_oferta'],
      [...ArticuloCsvContract.columnasConIdsAnteriores, 'precio_oferta'],
      [...ArticuloCsvContract.columnasConIdsAnteriores, 'eliminar_producto'],
      [...ArticuloCsvContract.columnasConIdsAnteriores, 'accion_oferta'],
    ]) {
      expect(revisar([], columnas: columnas).erroresEstructurales, isTrue);
    }
  });
}
