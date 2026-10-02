import 'dart:async';

import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/import/articulo_import_progreso.dart';
import 'package:pos_flutter/application/import/articulo_import_lote_fallido.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/export/articulo_catalog_export_service.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/domain/articulos/articulo_detalle.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/articulo_vinculado_categoria.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/domain/repositories/unidad_inventario_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/carga_masiva/bulk_import_screen.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late _FakeExportService exportador;
  late ShareParams? compartido;

  const encabezado =
      'categoria,nombre_articulo,tipo_venta,unidad_venta,'
      'nombre_variante,precio_venta,precio_coste,seguimiento_existencias,'
      'existencias,codigo_barras';

  /// El selector ya devuelve el archivo leído, así que el test no toca disco.
  ArchivoCargaMasiva archivo(String nombre, String contenido) =>
      (nombre: nombre, contenido: contenido);

  String csv(List<String> filas) => '$encabezado\n${filas.join('\n')}\n';

  String fila(List<String> campos) => campos.join(',');

  Future<void> pump(
    WidgetTester tester, {
    List<ArticuloListado>? catalogo,
    ArchivoCargaMasiva? archivoElegido,
    Future<ArchivoCargaMasiva?> Function()? pickFile,
    _FakeExportService? servicio,
    ArticuloImportBatchService? batchService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BulkImportScreen(
          categoriaRepository: _FakeCategoriaRepository(),
          productoRepository: _FakeProductoRepository(catalogo ?? const []),
          unidadInventarioRepository: const _FakeUnidadInventarioRepository(),
          exportService: servicio ?? exportador,
          importService: const ArticuloImportCsv(),
          batchService: batchService,
          pickFile: pickFile ?? () async => archivoElegido,
          shareFile: (params) async {
            compartido = params;
            return const ShareResult('', ShareResultStatus.success);
          },
        ),
      ),
    );
  }

  setUp(() {
    exportador = _FakeExportService();
    compartido = null;
  });

  testWidgets('ofrece exactamente dos acciones: plantilla y archivo', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('CARGA MASIVA'), findsOneWidget);
    expect(find.byKey(const Key('download_template_button')), findsOneWidget);
    expect(
      find.byKey(const Key('pick_bulk_import_file_button')),
      findsOneWidget,
    );
    // Sin un archivo revisado todavía no se ofrece importar.
    expect(find.textContaining('Importar'), findsNothing);
    expect(find.byKey(const Key('bulk_import_report')), findsNothing);
  });

  testWidgets(
    'descargar plantilla usa el servicio de exportación y lo comparte',
    (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('download_template_button')));
      await tester.pumpAndSettle();

      expect(exportador.plantillas, 1);
      expect(exportador.catalogos, 0);
      final compartidoConPlantilla = compartido!;
      expect(
        compartidoConPlantilla.files!.single.path,
        '/tmp/plantilla_catalogo.csv',
      );
      expect(
        compartidoConPlantilla.fileNameOverrides!.single,
        'plantilla_catalogo.csv',
      );
      expect(
        find.text('Se descargó la plantilla del catálogo.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('una falla al bajar la plantilla avisa y rehabilita el botón', (
    tester,
  ) async {
    await pump(tester, servicio: _FakeExportService(falla: true));

    await tester.tap(find.byKey(const Key('download_template_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo descargar la plantilla. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    final boton = tester.widget<OutlinedButton>(
      find.byKey(const Key('download_template_button')),
    );
    expect(boton.onPressed, isNotNull);
  });

  testWidgets('elegir archivo muestra las filas válidas y los problemas', (
    tester,
  ) async {
    final elegido = archivo(
      'catalogo.csv',
      csv([
        fila(['Bebidas', 'Café', 'unidad', '', '', '45.50', '', 'no', '0', '']),
        fila(['Bebidas', 'Té', 'unidad', '', '', '30', '', 'no', '0', '']),
        // Categoría que no existe: solo esta fila se rechaza.
        fila(['Licores', 'Ron', 'unidad', '', '', '120', '', 'no', '0', '']),
      ]),
    );
    await pump(tester, archivoElegido: elegido);

    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bulk_import_file_name')), findsOneWidget);
    expect(
      find.text('catalogo.csv'),
      findsOneWidget,
      reason: 'La pantalla tiene que decir qué archivo se revisó.',
    );
    expect(
      find.text('2 artículos y 2 filas listos para dar de alta.'),
      findsOneWidget,
    );
    expect(find.text('1 problema:'), findsOneWidget);
    expect(
      find.textContaining(
        'Línea 4 · categoria: La categoría "Licores" no existe.',
      ),
      findsOneWidget,
    );
    // Sin errores de encabezado se puede seguir adelante.
    expect(find.byKey(const Key('bulk_import_blocked')), findsNothing);
  });

  testWidgets('el interruptor ofrece importar solo las filas válidas', (
    tester,
  ) async {
    final elegido = archivo(
      'catalogo.csv',
      csv([
        fila(['Bebidas', 'Café', 'unidad', '', '', '45.50', '', 'no', '0', '']),
        fila(['Licores', 'Ron', 'unidad', '', '', '120', '', 'no', '0', '']),
      ]),
    );
    await pump(tester, archivoElegido: elegido);

    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('import_only_valid_switch')),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('import_only_valid_switch')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('import_only_valid_switch')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('un encabezado que no coincide bloquea la importación', (
    tester,
  ) async {
    final elegido = archivo(
      'catalogo.csv',
      'Bebidas,Café,unidad,,,45.50,,no,0,\n',
    );
    await pump(tester, archivoElegido: elegido);

    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bulk_import_blocked')), findsOneWidget);
    expect(
      find.text('0 artículos y 0 filas listos para dar de alta.'),
      findsOneWidget,
    );
    final interruptor = tester.widget<SwitchListTile>(
      find.byKey(const Key('import_only_valid_switch')),
    );
    expect(interruptor.onChanged, isNull);
  });

  testWidgets('un artículo que ya existe en el catálogo se rechaza', (
    tester,
  ) async {
    final elegido = archivo(
      'catalogo.csv',
      csv([
        fila(['Bebidas', 'Café', 'unidad', '', '', '45.50', '', 'no', '0', '']),
      ]),
    );
    await pump(
      tester,
      archivoElegido: elegido,
      catalogo: const [
        ArticuloListado(
          productoId: 'p-1',
          nombre: 'Café',
          activo: true,
          categoriaId: null,
          categoriaNombre: null,
          categoriaColor: null,
          variantesActivas: [
            VarianteListado(
              varianteId: 'v-1',
              nombre: null,
              precioVentaMenor: 4550,
              orden: 0,
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Ya existe un producto llamado "Café".'),
      findsOneWidget,
    );
    expect(
      find.text('0 artículos y 0 filas listos para dar de alta.'),
      findsOneWidget,
    );
  });

  Future<void> revisar(
    WidgetTester tester,
    _FakeBatchService servicio, {
    bool conError = false,
  }) async {
    await pump(
      tester,
      batchService: servicio,
      archivoElegido: archivo(
        'carga.csv',
        csv([
          fila(['', 'Café', 'unidad', '', '', '45.50', '', 'no', '0', '']),
          if (conError)
            fila(['', 'Inválido', 'unidad', '', '', '0', '', 'no', '0', '']),
        ]),
      ),
    );
    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('confirm_bulk_import_button')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('revisar, abrir confirmación y cancelar no escribe nada', (
    tester,
  ) async {
    final servicio = _FakeBatchService();
    await revisar(tester, servicio);
    expect(servicio.llamadas, 0);
    await tester.tap(find.byKey(const Key('confirm_bulk_import_button')));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar carga masiva'), findsOneWidget);
    expect(servicio.llamadas, 0);
    await tester.tap(find.byKey(const Key('cancel_bulk_import_dialog')));
    await tester.pumpAndSettle();
    expect(servicio.llamadas, 0);
    expect(find.byKey(const Key('bulk_import_progress')), findsNothing);
  });

  testWidgets('confirmar importa una vez, muestra progreso y bloquea repetir', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final servicio = _FakeBatchService(gate: Completer<void>());
    await revisar(tester, servicio);
    await tester.tap(find.byKey(const Key('confirm_bulk_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept_bulk_import_dialog')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(servicio.llamadas, 1);
    expect(servicio.productos.single.nombre, 'Café');
    expect(find.text('Lotes: 0/1'), findsOneWidget);
    expect(find.text('Artículos importados: 0/1'), findsOneWidget);
    expect(find.text('Artículos fallidos: 0'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm_bulk_import_button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('pick_bulk_import_file_button')),
          )
          .onPressed,
      isNull,
    );
    servicio.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Carga finalizada'), findsOneWidget);
    expect(find.text('Lotes: 1/1'), findsOneWidget);
    expect(find.text('Artículos importados: 1/1'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm_bulk_import_button')),
          )
          .onPressed,
      isNull,
    );
    expect(servicio.llamadas, 1);
  });

  testWidgets('con errores exige solo válidas y confirma las omisiones', (
    tester,
  ) async {
    final servicio = _FakeBatchService();
    await revisar(tester, servicio, conError: true);
    final switchFinder = find.byKey(const Key('import_only_valid_switch'));
    await Scrollable.ensureVisible(
      tester.element(switchFinder),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm_bulk_import_button')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('confirm_bulk_import_button')),
    );
    await tester.tap(find.byKey(const Key('confirm_bulk_import_button')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Las filas con problemas se omitirán.'),
      findsOneWidget,
    );
    expect(servicio.llamadas, 0);
    await tester.tap(find.byKey(const Key('accept_bulk_import_dialog')));
    await tester.pumpAndSettle();
    expect(servicio.productos.map((p) => p.nombre), ['Café']);
  });

  testWidgets('el lote fallido se reporta con artículos, líneas y motivo', (
    tester,
  ) async {
    final servicio = _FakeBatchService(falla: true);
    await revisar(tester, servicio);
    await tester.tap(find.byKey(const Key('confirm_bulk_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept_bulk_import_dialog')));
    await tester.pumpAndSettle();
    expect(find.text('Artículos fallidos: 1'), findsOneWidget);
    expect(
      find.textContaining(
        'Lote 1: 1 artículos revertidos. Líneas: 2. Fallo del lote',
      ),
      findsOneWidget,
    );
    expect(find.text('Artículos: Café'), findsOneWidget);
  });

  testWidgets('archivo de catálogo existente no ofrece una nueva alta', (
    tester,
  ) async {
    final servicio = _FakeBatchService();
    await pump(
      tester,
      batchService: servicio,
      catalogo: const [
        ArticuloListado(
          productoId: 'p',
          nombre: 'Café',
          activo: true,
          categoriaId: null,
          categoriaNombre: null,
          categoriaColor: null,
          variantesActivas: [],
        ),
      ],
      archivoElegido: archivo(
        'catalogo.csv',
        csv([
          fila(['', 'Café', 'unidad', '', '', '45.50', '', 'no', '0', '']),
        ]),
      ),
    );
    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirm_bulk_import_button')),
      200,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm_bulk_import_button')),
          )
          .onPressed,
      isNull,
    );
    expect(servicio.llamadas, 0);
  });

  testWidgets('cancelar el selector no cambia nada', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bulk_import_report')), findsNothing);
    expect(find.byKey(const Key('bulk_import_file_name')), findsNothing);
  });

  testWidgets('un archivo que no se puede leer avisa y no rompe la pantalla', (
    tester,
  ) async {
    // El selector deja volar el error de lectura y la pantalla lo traduce.
    await pump(
      tester,
      pickFile: () async => throw const FileSystemException('x'),
    );

    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo leer el archivo. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('bulk_import_report')), findsNothing);
    // El selector se puede volver a usar.
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('pick_bulk_import_file_button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('un archivo vacío se explica como archivo vacío', (tester) async {
    await pump(tester, archivoElegido: archivo('vacio.csv', ''));

    await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
    await tester.pumpAndSettle();

    expect(find.text('archivo: El archivo está vacío.'), findsOneWidget);
    expect(find.byKey(const Key('bulk_import_blocked')), findsOneWidget);
  });

  testWidgets('las reglas del archivo se leen sin salir de la pantalla', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const Key('bulk_import_rules')), findsOneWidget);
    expect(find.text('Reglas del archivo'), findsOneWidget);
    expect(
      find.textContaining('Reemplaza o elimina las filas de ejemplo'),
      findsOneWidget,
    );
    expect(find.textContaining('g, kg, ml o l'), findsOneWidget);
    expect(find.textContaining('Máximo 500 filas'), findsOneWidget);
  });
}

class _FakeExportService implements ArticuloCatalogExportService {
  _FakeExportService({this.falla = false});

  final bool falla;
  int plantillas = 0;
  int catalogos = 0;

  @override
  Future<ArticuloExportArchivo> exportarPlantilla() async {
    plantillas++;
    if (falla) throw StateError('export error');
    return const ArticuloExportArchivo(
      ruta: '/tmp/plantilla_catalogo.csv',
      productos: 0,
      filas: 0,
    );
  }

  @override
  Future<ArticuloExportArchivo> exportarNotasColumnas() async =>
      throw UnimplementedError();

  @override
  Future<ArticuloExportArchivo> exportarCatalogo(
    ArticuloExportFiltro filtro,
  ) async {
    catalogos++;
    throw UnimplementedError();
  }

  @override
  Future<ArticuloExportArchivo> exportarCatalogoPdf(
    ArticuloExportFiltro filtro,
  ) => throw UnimplementedError();
}

class _FakeCategoriaRepository implements CategoriaRepository {
  @override
  Stream<List<Categoria>> watchCategorias() => Stream.value(_categorias);

  @override
  Future<List<Categoria>> obtenerCategorias() async => _categorias;

  static const _categorias = [
    Categoria(
      id: 'cat-bebidas',
      nombre: 'Bebidas',
      color: ColorCategoria.blue,
      orden: 0,
    ),
  ];
}

class _FakeProductoRepository implements ProductoRepository {
  _FakeProductoRepository(this.articulos);

  final List<ArticuloListado> articulos;

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) => Stream.value(articulos);

  @override
  Stream<int> watchVariantesActivasCount() => throw UnimplementedError();

  @override
  Future<ArticuloDetalle?> obtenerDetalle(String productoId) =>
      throw UnimplementedError();

  @override
  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  ) => throw UnimplementedError();
}

class _FakeUnidadInventarioRepository implements UnidadInventarioRepository {
  const _FakeUnidadInventarioRepository();

  @override
  Future<List<UnidadInventario>> obtenerUnidadesActivas() async => _unidades;

  @override
  Future<UnidadInventario?> obtenerUnidadPorId(String unidadId) async {
    for (final unidad in _unidades) {
      if (unidad.id == unidadId) return unidad;
    }
    return null;
  }
}

const _unidades = <UnidadInventario>[
  UnidadInventario(
    id: InventoryUnitIds.piece,
    code: 'piece',
    nombre: 'Pieza',
    simbolo: 'pza',
    dimension: DimensionUnidad.count,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  ),
  UnidadInventario(
    id: InventoryUnitIds.gram,
    code: 'g',
    nombre: 'Gramo',
    simbolo: 'g',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  ),
  UnidadInventario(
    id: InventoryUnitIds.kilogram,
    code: 'kg',
    nombre: 'Kilogramo',
    simbolo: 'kg',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  ),
  UnidadInventario(
    id: InventoryUnitIds.milliliter,
    code: 'ml',
    nombre: 'Mililitro',
    simbolo: 'ml',
    dimension: DimensionUnidad.volume,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  ),
  UnidadInventario(
    id: InventoryUnitIds.liter,
    code: 'l',
    nombre: 'Litro',
    simbolo: 'L',
    dimension: DimensionUnidad.volume,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  ),
];

class _FakeBatchService implements ArticuloImportBatchService {
  _FakeBatchService({this.gate, this.falla = false});
  final Completer<void>? gate;
  final bool falla;
  int llamadas = 0;
  List<ArticuloImportProducto> productos = [];

  @override
  Future<ArticuloImportProgreso> importar(
    List<ArticuloImportProducto> productos, {
    required void Function(ArticuloImportProgreso) onProgress,
  }) async {
    llamadas++;
    this.productos = productos;
    onProgress(
      ArticuloImportProgreso(
        lotesTotales: 1,
        productosTotales: productos.length,
      ),
    );
    if (gate != null) await gate!.future;
    final resultado = ArticuloImportProgreso(
      lotesTotales: 1,
      lotesProcesados: 1,
      productosTotales: productos.length,
      productosImportados: falla ? 0 : productos.length,
      productosFallidos: falla ? productos.length : 0,
      lotesFallidos: falla
          ? [
              ArticuloImportLoteFallido(
                numero: 1,
                productos: productos.map((p) => p.nombre).toList(),
                lineas: [2],
                motivo: 'Fallo del lote',
              ),
            ]
          : [],
    );
    onProgress(resultado);
    return resultado;
  }
}
