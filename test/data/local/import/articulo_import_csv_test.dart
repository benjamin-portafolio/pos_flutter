import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/domain/articulos/sale_mode.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';

void main() {
  const servicio = ArticuloImportCsv();

  /// Las 5 unidades que se siembran en cada dispositivo (H8). `piece` está
  /// porque es la unidad del recurso en venta por unidad (H9), no porque sirva
  /// para venta por fracción.
  final unidades = <UnidadInventario>[
    const UnidadInventario(
      id: 'u-piece',
      code: 'piece',
      nombre: 'Pieza',
      simbolo: 'pza',
      dimension: DimensionUnidad.count,
      factorAtomico: 1,
      maximosDecimales: 0,
      activa: true,
    ),
    const UnidadInventario(
      id: 'u-g',
      code: 'g',
      nombre: 'Gramo',
      simbolo: 'g',
      dimension: DimensionUnidad.mass,
      factorAtomico: 1,
      maximosDecimales: 0,
      activa: true,
    ),
    const UnidadInventario(
      id: 'u-kg',
      code: 'kg',
      nombre: 'Kilogramo',
      simbolo: 'kg',
      dimension: DimensionUnidad.mass,
      factorAtomico: 1000,
      maximosDecimales: 3,
      activa: true,
    ),
    const UnidadInventario(
      id: 'u-ml',
      code: 'ml',
      nombre: 'Mililitro',
      simbolo: 'ml',
      dimension: DimensionUnidad.volume,
      factorAtomico: 1,
      maximosDecimales: 0,
      activa: true,
    ),
    const UnidadInventario(
      id: 'u-l',
      code: 'l',
      nombre: 'Litro',
      simbolo: 'L',
      dimension: DimensionUnidad.volume,
      factorAtomico: 1000,
      maximosDecimales: 3,
      activa: true,
    ),
  ];

  /// Catálogo de referencia: tres categorías, las 5 unidades y los artículos
  /// que se le pidan. Los ids siguen la convención del repo.
  ArticuloImportCatalogo catalogo({
    Set<String> nombres = const {},
    List<ArticuloImportCategoria>? categorias,
  }) => ArticuloImportCatalogo(
    categorias:
        categorias ??
        const [
          ArticuloImportCategoria(id: 'cat-bebidas', nombre: 'Bebidas'),
          ArticuloImportCategoria(id: 'cat-frutas', nombre: 'Frutas'),
          ArticuloImportCategoria(id: 'cat-abarrotes', nombre: 'Abarrotes'),
        ],
    unidades: unidades,
    nombresArticulos: nombres,
  );

  /// Archivo con el encabezado real del compositor, para que el test use el
  /// contrato de columnas y no una copia que puede quedar vieja.
  String archivo(List<String> filas) =>
      '${ArticuloCatalogCsv.columnas.join(',')}\n${filas.join('\n')}\n';

  /// Une los campos con el delimitador del contrato.
  String fila(List<String> campos) => campos.join(',');

  ArticuloImportReporte validar(
    List<String> filas, {
    ArticuloImportCatalogo? catalogo,
  }) => servicio.validar(
    archivo(filas),
    catalogo:
        catalogo ??
        ArticuloImportCatalogo(
          categorias: const [
            ArticuloImportCategoria(id: 'cat-bebidas', nombre: 'Bebidas'),
            ArticuloImportCategoria(id: 'cat-frutas', nombre: 'Frutas'),
            ArticuloImportCategoria(id: 'cat-abarrotes', nombre: 'Abarrotes'),
          ],
          unidades: unidades,
        ),
  );

  group('estructura', () {
    test('un archivo vacío es un error, no un archivo sin filas', () {
      final reporte = servicio.validar('', catalogo: catalogo());

      expect(reporte.productos, isEmpty);
      expect(reporte.errores.single.columna, 'archivo');
      expect(reporte.errores.single.motivo, 'El archivo está vacío.');
      expect(reporte.importable, isFalse);
    });

    test('el encabezado tiene que coincidir exactamente', () {
      // Un archivo cuyos datos empiezan en la primera línea: no hay
      // encabezado y las diez columnas obligatorias faltan.
      final reporte = servicio.validar(
        'Bebidas,Cafe,unidad,,,45.50,,no,0,\n',
        catalogo: catalogo(),
      );

      // Sin encabezado no hay nada que interpretar: el archivo se rechaza
      // entero y no se ofrecen filas válidas.
      expect(reporte.errores, hasLength(ArticuloCatalogCsv.columnas.length));
      expect(
        reporte.errores.map((error) => error.columna),
        containsAll(ArticuloCatalogCsv.columnas),
      );
      expect(
        reporte.errores.every(
          (error) => error.motivo.contains('Falta la columna'),
        ),
        isTrue,
      );
      expect(reporte.errores.every((error) => error.linea == null), isTrue);
      expect(reporte.importable, isFalse);
    });

    test('una columna desconocida es error y no se ignora', () {
      final reporte = servicio.validar(
        '${ArticuloCatalogCsv.columnas.join(',')},columna_inventada\n'
        'Bebidas,Cafe,unidad,,,45.50,,,no,0,,x\n',
        catalogo: catalogo(),
      );

      expect(reporte.errores.single.columna, 'columna_inventada');
      expect(reporte.errores.single.motivo, contains('Columna desconocida'));
      expect(reporte.errores.single.linea, isNull);
      expect(reporte.importable, isFalse);
    });

    test('una columna obligatoria faltante es error', () {
      final columnas = ArticuloCatalogCsv.columnas
          .where((columna) => columna != 'precio_venta')
          .toList();
      final reporte = servicio.validar(
        '${columnas.join(',')}\nBebidas,Cafe,unidad,,,,,,no,0,\n',
        catalogo: catalogo(),
      );

      expect(reporte.errores.single.columna, 'precio_venta');
      expect(reporte.errores.single.motivo, contains('Falta la columna'));
      expect(reporte.importable, isFalse);
    });

    test('las columnas en otro orden no se aceptan', () {
      final columnas = List<String>.of(ArticuloCatalogCsv.columnas);
      final primero = columnas[1];
      columnas[1] = columnas[4];
      columnas[4] = primero;
      final reporte = servicio.validar(
        '${columnas.join(',')}\nBebidas,Cafe,unidad,,,45.50,,,no,0,\n',
        catalogo: catalogo(),
      );

      expect(reporte.errores.single.columna, 'encabezado');
      expect(reporte.errores.single.motivo, contains('coincidir exactamente'));
      expect(reporte.importable, isFalse);
    });

    test('una fila con un número de campos distinto del encabezado', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '45.50', '', 'no', '0', '']),
        // Le faltan dos campos.
        fila(['Bebidas', 'Agua', 'unidad', '', '', '25', '', 'no', '0']),
      ]);

      expect(reporte.productos, hasLength(1));
      final error = reporte.errores.single;
      expect(error.linea, 3);
      expect(error.columna, 'archivo');
      expect(error.motivo, contains('9 campos'));
      expect(error.descripcion, 'Línea 3 · archivo');
    });

    test('más de 500 filas se rechaza antes de mirar las filas', () {
      final reporte = validar([
        for (var index = 0; index <= 500; index++)
          fila([
            'Bebidas',
            'Articulo $index',
            'unidad',
            '',
            '',
            '10',
            '',
            'no',
            '0',
            '',
          ]),
      ]);

      expect(reporte.errores.single.columna, 'archivo');
      expect(reporte.errores.single.motivo, contains('501 filas'));
      expect(reporte.errores.single.motivo, contains('500'));
    });

    test('500 filas exactas sí se validan', () {
      final reporte = validar([
        for (var index = 0; index < 500; index++)
          fila([
            'Bebidas',
            'Articulo $index',
            'unidad',
            '',
            '',
            '10',
            '',
            'no',
            '0',
            '',
          ]),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos, hasLength(500));
    });

    test('las líneas en blanco se ignoran y no cuentan como filas', () {
      final reporte = validar([
        '',
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '45.50', '', 'no', '0', '']),
        '   ',
        fila(['Bebidas', 'Agua', 'unidad', '', '', '25', '', 'no', '0', '']),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos, hasLength(2));
    });

    test('un nombre con "," o comillas no parte la fila', () {
      // El compositor entrecomilla esos nombres (H17) y el importador respeta el
      // entrecomillado, así que el round-trip de un nombre con `,` es seguro.
      final reporte = validar([
        fila([
          'Bebidas',
          '"Panadería, Industrial"',
          'unidad',
          '',
          '',
          '45.50',
          '',
          'no',
          '0',
          '',
        ]),
        fila([
          'Bebidas',
          '"Fruta del ""nombre"""',
          'unidad',
          '',
          '',
          '25',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos.map((producto) => producto.nombre), [
        'Panadería, Industrial',
        'Fruta del "nombre"',
      ]);
    });
  });

  group('errores por fila', () {
    test('nombre_articulo vacío', () {
      final reporte = validar([
        fila(['Bebidas', '   ', 'unidad', '', '', '45.50', '', 'no', '0', '']),
      ]);

      expect(reporte.errores.single.linea, 2);
      expect(reporte.errores.single.columna, 'nombre_articulo');
      expect(reporte.errores.single.motivo, contains('no puede estar vacío'));
    });

    test('nombre_articulo de más de 160 caracteres', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'A' * 161,
          'unidad',
          '',
          '',
          '45.50',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'nombre_articulo');
      expect(reporte.errores.single.motivo, contains('161 caracteres'));
    });

    test('nombre_articulo repetido dentro del archivo con otra escritura', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Naranja',
          'fraccion',
          'kg',
          'Valencia',
          '18',
          '',
          'no',
          '0',
          '',
        ]),
        // Mismo nombre, otra escritura: se fusionarían en un solo producto sin
        // que nadie lo pidiera.
        fila([
          'Frutas',
          'naranja ',
          'fraccion',
          'kg',
          'Sevillana',
          '25',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.linea, 3);
      expect(reporte.errores.single.columna, 'nombre_articulo');
      expect(reporte.errores.single.motivo, contains('mismo artículo'));
    });

    test('nombre_articulo ya existente en el catálogo', () {
      final reporte = validar([
        fila(['Bebidas', 'Café', 'unidad', '', '', '45.50', '', 'no', '0', '']),
      ], catalogo: catalogo(nombres: {'Café'}));

      expect(reporte.errores.single.columna, 'nombre_articulo');
      expect(
        reporte.errores.single.motivo,
        'Ya existe un producto llamado "Café".',
      );
      expect(reporte.productos, isEmpty);
    });

    test('nombre_articulo se compara sin mayúsculas ni espacios', () {
      final reporte = validar([
        fila([
          'Bebidas',
          ' café ',
          'unidad',
          '',
          '',
          '45.50',
          '',
          'no',
          '0',
          '',
        ]),
      ], catalogo: catalogo(nombres: {'CAFÉ'}));

      expect(
        reporte.errores.single.motivo,
        'Ya existe un producto llamado "café".',
      );
    });

    test('categoría que no existe', () {
      final reporte = validar([
        fila(['Licores', 'Ron', 'unidad', '', '', '120', '', 'no', '0', '']),
      ]);

      expect(reporte.errores.single.columna, 'categoria');
      expect(reporte.errores.single.motivo, contains('no existe'));
      expect(reporte.errores.single.motivo, contains('no se crean'));
    });

    test('categoría vacía significa Sin categoría', () {
      final reporte = validar([
        fila(['', 'Cafe', 'unidad', '', '', '45.50', '', 'no', '0', '']),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos.single.categoriaId, isNull);
    });

    test('categoría resuelta por nombre', () {
      final reporte = validar([
        fila([
          'Frutas',
          'Naranja',
          'fraccion',
          'kg',
          '',
          '18',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos.single.categoriaId, 'cat-frutas');
    });

    test('tipo_venta distinto de unidad o fraccion', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'peso', '', '', '45.50', '', 'no', '0', '']),
      ]);

      expect(reporte.errores.single.columna, 'tipo_venta');
      expect(reporte.errores.single.motivo, contains('"peso" no existe'));
    });

    test('tipo_venta omitido vale unidad', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', '', '', '', '45.50', '', 'no', '0', '']),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos.single.modoVenta, SaleMode.unit);
    });

    test('unidad_venta vacía con tipo_venta fraccion', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'fraccion',
          '',
          '',
          '45.50',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'unidad_venta');
      expect(reporte.errores.single.motivo, contains('obligatoria'));
    });

    test('unidad_venta fuera de g, kg, ml y l', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'fraccion',
          'lb',
          '',
          '45.50',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'unidad_venta');
      expect(reporte.errores.single.motivo, contains('g, kg, ml o l'));
    });

    test('piece no sirve para venta por fracción', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'fraccion',
          'piece',
          '',
          '45.50',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'unidad_venta');
      expect(reporte.errores.single.motivo, contains('g, kg, ml o l'));
    });

    test('unidad_venta informada con tipo_venta unidad', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          'kg',
          '',
          '45.50',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'unidad_venta');
      expect(reporte.errores.single.motivo, contains('no se escribe'));
    });

    test('nombre_variante vacío en un producto con más de una variante', () {
      final reporte = validar([
        fila([
          'Frutas',
          'Naranja',
          'fraccion',
          'kg',
          'Valencia',
          '18',
          '',
          'no',
          '0',
          '',
        ]),
        fila([
          'Frutas',
          'Naranja',
          'fraccion',
          'kg',
          '',
          '25',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.linea, 3);
      expect(reporte.errores.single.columna, 'nombre_variante');
      // La variante sin nombre no llega al producto: el recurso de inventario se
      // llamaría exactamente igual al producto (H1).
      expect(reporte.productos.single.variantes, hasLength(1));
      expect(reporte.productos.single.variantes.single.nombre, 'Valencia');
    });

    test('nombre_variante repetido dentro del mismo producto', () {
      final reporte = validar([
        fila([
          'Frutas',
          'Naranja',
          'fraccion',
          'kg',
          'Valencia',
          '18',
          '',
          'no',
          '0',
          '',
        ]),
        fila([
          'Frutas',
          'Naranja',
          'fraccion',
          'kg',
          'valencia',
          '25',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      // Se reporta en la fila sobrante, y el producto conserva la primera: el
      // archivo con problemas importa solo las filas válidas.
      expect(reporte.errores.single.linea, 3);
      expect(reporte.errores.single.columna, 'nombre_variante');
      expect(reporte.errores.single.motivo, contains('repetida'));
      expect(reporte.productos.single.variantes, hasLength(1));
      expect(reporte.productos.single.variantes.single.nombre, 'Valencia');
      expect(reporte.productos.single.variantes.single.precioVentaMinor, 1800);
    });

    test('precio_venta vacío', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '', '', 'no', '0', '']),
      ]);

      expect(reporte.errores.single.columna, 'precio_venta');
      expect(
        reporte.errores.single.motivo,
        'El precio de venta es obligatorio.',
      );
    });

    test('precio_venta no numérico', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          '',
          '',
          'veinte',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'precio_venta');
      expect(
        reporte.errores.single.motivo,
        contains('no es un importe válido'),
      );
    });

    test('precio_venta cero', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '0', '', 'no', '0', '']),
      ]);

      expect(reporte.errores.single.columna, 'precio_venta');
      expect(reporte.errores.single.motivo, contains('mayor que 0'));
    });

    test('precio_venta negativo', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '-5', '', 'no', '0', '']),
      ]);

      expect(reporte.errores.single.columna, 'precio_venta');
      expect(reporte.errores.single.motivo, contains('mayor que 0'));
    });

    test('precio_coste no numérico', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          '',
          '',
          '45.50',
          'gratis',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'precio_coste');
      expect(
        reporte.errores.single.motivo,
        contains('no es un importe válido'),
      );
    });

    test('precio_coste negativo', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          '',
          '',
          '45.50',
          '-1',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'precio_coste');
      expect(reporte.errores.single.motivo, contains('no puede ser negativo'));
    });

    test('precio_coste vacío es costo desconocido, no cero', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '45.50', '', 'no', '0', '']),
      ]);

      expect(reporte.errores, isEmpty);
      expect(
        reporte.productos.single.variantes.single.precioCosteMinor,
        isNull,
      );
    });

    test('seguimiento_existencias distinto de si o no', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          '',
          '',
          '45.50',
          '',
          'quizá',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'seguimiento_existencias');
      expect(reporte.errores.single.motivo, contains('"si" o "no"'));
    });

    test('seguimiento_existencias omitido vale no', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '45.50', '', '', '0', '']),
      ]);

      expect(reporte.errores, isEmpty);
      expect(
        reporte.productos.single.variantes.single.seguimientoExistencias,
        isFalse,
      );
    });

    test('existencias vacía con seguimiento si', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Arroz',
          'fraccion',
          'kg',
          '',
          '60',
          '',
          'si',
          '',
          '',
        ]),
      ]);

      expect(reporte.errores.single.linea, 2);
      expect(reporte.errores.single.columna, 'existencias');
      expect(reporte.errores.single.motivo, contains('obligatorias'));
    });

    test('existencias en cero con seguimiento si es válido', () {
      final reporte = validar([
        fila([
          'Abarrotes',
          'Arroz',
          'fraccion',
          'kg',
          '',
          '60',
          '',
          'si',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos.single.variantes.single.existenciasAtomic, 0);
    });

    test('existencias no numérica', () {
      final reporte = validar([
        fila([
          'Abarrotes',
          'Arroz',
          'fraccion',
          'kg',
          '',
          '60',
          '',
          'si',
          'mucho',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'existencias');
      expect(
        reporte.errores.single.motivo,
        contains('no es una cantidad válida'),
      );
    });

    test('existencias negativas', () {
      final reporte = validar([
        fila([
          'Abarrotes',
          'Arroz',
          'fraccion',
          'kg',
          '',
          '60',
          '',
          'si',
          '-5',
          '',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'existencias');
      expect(
        reporte.errores.single.motivo,
        contains('no es una cantidad válida'),
      );
    });

    test('codigo_barras con caracteres no numéricos', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          '',
          '',
          '45.50',
          '',
          'no',
          '0',
          'ABC123',
        ]),
      ]);

      expect(reporte.errores.single.columna, 'codigo_barras');
      expect(reporte.errores.single.motivo, contains('solo admite dígitos'));
    });

    test('codigo_barras de más de 32 dígitos', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          '',
          '',
          '45.50',
          '',
          'no',
          '0',
          '1' * 33,
        ]),
      ]);

      expect(reporte.errores.single.columna, 'codigo_barras');
      expect(reporte.errores.single.motivo, contains('hasta 32'));
    });

    test('codigo_barras de 32 dígitos es válido', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          '',
          '',
          '45.50',
          '',
          'no',
          '0',
          '1' * 32,
        ]),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos.single.variantes.single.codigoBarras, '1' * 32);
    });
  });

  group('conversión a centavos', () {
    test('redondeo half-up a dos decimales, una sola vez en el límite', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Naranja',
          'fraccion',
          'kg',
          '',
          '18.005',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos.single.variantes.single.precioVentaMinor, 1801);
    });

    test('18.004 entra como 18.00', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Naranja',
          'fraccion',
          'kg',
          '',
          '18.004',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.productos.single.variantes.single.precioVentaMinor, 1800);
    });

    test('el tercer dígito decide el redondeo', () {
      for (final (importe, esperado) in [
        ('1.004', 100),
        ('1.005', 101),
        ('1.014', 101),
        ('1.015', 102),
      ]) {
        final reporte = validar([
          fila([
            'Bebidas',
            'Naranja',
            'fraccion',
            'kg',
            '',
            importe,
            '',
            'no',
            '0',
            '',
          ]),
        ]);

        expect(
          reporte.productos.single.variantes.single.precioVentaMinor,
          esperado,
          reason: 'El importe $importe debería entrar como $esperado centavos.',
        );
      }
    });

    test('el precio de coste también se redondea half-up', () {
      final reporte = validar([
        fila([
          'Bebidas',
          'Cafe',
          'unidad',
          '',
          '',
          '45.505',
          '10.005',
          'no',
          '0',
          '',
        ]),
      ]);

      final variante = reporte.productos.single.variantes.single;
      expect(variante.precioVentaMinor, 4551);
      expect(variante.precioCosteMinor, 1001);
    });

    test('el punto decimal es el separador del contrato, no la coma', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '45.50', '', 'no', '0', '']),
      ]);

      expect(reporte.errores, isEmpty);
      expect(reporte.productos.single.variantes.single.precioVentaMinor, 4550);
    });
  });

  group('derivaciones y agrupación', () {
    test('la cantidad de referencia sale del factor atómico de la unidad', () {
      final reporte = validar([
        fila([
          'Frutas',
          'Naranja',
          'fraccion',
          'kg',
          '',
          '18',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      // H8: la cantidad de referencia es el `atomicFactor` de la unidad, no una
      // columna del archivo.
      expect(reporte.productos.single.cantidadReferenciaPrecioAtomic, 1000);
    });

    test('la unidad del recurso es la misma que la de venta en fracción', () {
      final reporte = validar([
        fila([
          'Frutas',
          'Naranja',
          'fraccion',
          'l',
          '',
          '18',
          '',
          'no',
          '0',
          '',
        ]),
      ]);

      expect(reporte.productos.single.unidadVentaId, 'u-l');
      expect(reporte.productos.single.unidadInventarioId, 'u-l');
    });

    test('la unidad del recurso es piece en venta por unidad', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '45.50', '', 'si', '3', '']),
      ]);

      expect(reporte.productos.single.unidadVentaId, isNull);
      expect(reporte.productos.single.unidadInventarioId, 'u-piece');
      // piece no admite decimales, así que "3" son 3 átomos.
      expect(reporte.productos.single.variantes.single.existenciasAtomic, 3);
    });

    test('las existencias se convierten a átomos de la unidad del recurso', () {
      final reporte = validar([
        fila([
          'Abarrotes',
          'Arroz',
          'fraccion',
          'kg',
          '',
          '60',
          '',
          'si',
          '120.5',
          '',
        ]),
      ]);

      expect(
        reporte.productos.single.variantes.single.existenciasAtomic,
        120500,
      );
    });

    test(
      'las filas del mismo producto se agrupan con sort_order desde cero',
      () {
        final reporte = validar([
          fila([
            'Frutas',
            'Naranja',
            'fraccion',
            'kg',
            'Valencia',
            '18',
            '',
            'no',
            '0',
            '',
          ]),
          fila(['Bebidas', 'Agua', 'unidad', '', '', '25', '', 'no', '0', '']),
          fila([
            'Frutas',
            'Naranja',
            'fraccion',
            'kg',
            'Sevillana',
            '25',
            '',
            'no',
            '0',
            '',
          ]),
          fila([
            'Frutas',
            'Naranja',
            'fraccion',
            'kg',
            'Sin pepas',
            '30',
            '',
            'no',
            '0',
            '',
          ]),
        ]);

        expect(reporte.errores, isEmpty);
        expect(reporte.productos, hasLength(2));
        expect(reporte.productos.first.nombre, 'Naranja');
        expect(reporte.productos.first.categoriaId, 'cat-frutas');
        expect(
          reporte.productos.first.variantes.map((variante) => variante.nombre),
          ['Valencia', 'Sevillana', 'Sin pepas'],
        );
        expect(
          reporte.productos.first.variantes.map(
            (variante) => variante.sortOrder,
          ),
          [0, 1, 2],
        );
        expect(reporte.filasValidas, 4);
      },
    );

    test('una sola variante sin nombre es válida', () {
      final reporte = validar([
        fila([
          'Abarrotes',
          'Arroz',
          'fraccion',
          'kg',
          '',
          '60',
          '',
          'si',
          '120',
          '',
        ]),
      ]);

      expect(reporte.errores, isEmpty);
      final producto = reporte.productos.single;
      expect(producto.variantes, hasLength(1));
      expect(producto.variantes.single.nombre, isNull);
    });

    test('el archivo no lleva identidad: nada se genera aquí', () {
      final reporte = validar([
        fila(['Bebidas', 'Cafe', 'unidad', '', '', '45.50', '', 'no', '0', '']),
      ]);

      // El id se genera al procesar (D4). La Fase 3 no escribe nada, así que
      // tampoco hay ningún identificador que reportar.
      expect(reporte.filasValidas, 1);
      expect(
        reporte.productos.single.toString(),
        isNot(contains('product_id')),
      );
      expect(
        reporte.productos.single.variantes.single.toString(),
        isNot(contains('variant_id')),
      );
    });
  });

  group('el archivo exportado vuelve a validarse sin cambios', () {
    test('el catálogo exportado es un archivo de carga válido', () {
      final exportado = ArticuloCatalogCsv.catalogo(const []);
      final reporte = servicio.validar(exportado, catalogo: catalogo());

      // Solo el encabezado, sin filas: no hay ni un error.
      expect(reporte.errores, isEmpty);
      expect(reporte.productos, isEmpty);
    });
  });
}
