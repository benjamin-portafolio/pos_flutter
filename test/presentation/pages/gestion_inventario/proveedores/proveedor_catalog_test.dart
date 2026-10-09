import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/proveedores/crear_proveedor_command.dart';
import 'package:pos_flutter/application/commands/proveedores/editar_proveedor_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/domain/proveedores/proveedor.dart';
import 'package:pos_flutter/domain/repositories/proveedor_repository.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/inventario/inventory_resource_filter.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/domain/repositories/recurso_inventario_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/proveedores/inventory_suppliers_tab.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/proveedores/proveedor_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/proveedores/models/proveedor_form_result.dart';
import '../../../../support/proveedor_harness.dart';

void main() {
  void catalogTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Drift programa la liberación de la consulta al cancelar el listener.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  late ProveedorHarness h;
  setUp(() => h = ProveedorHarness());
  tearDown(() => h.dispose());
  Finder field(String name) => find.byKey(Key('supplier_${name}_field'));
  final save = find.byKey(const Key('save_supplier_button'));

  Future<List<Proveedor>> read(WidgetTester tester) async =>
      (await tester.runAsync(() => h.repository.watchProveedores().first))!;
  Future<void> pumpCatalog(WidgetTester tester) async {
    await tester.runAsync(() => h.db.customSelect('SELECT 1').get());
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: _Categories(),
          productoRepository: _Products(),
          recursoInventarioRepository: _Resources(),
          proveedorRepository: h.repository,
          proveedorCommandService: h.service,
          appConfigController: h.config,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> suppliers(WidgetTester tester) async {
    await tester.ensureVisible(find.text('PROVEEDORES'));
    await tester.tap(find.text('PROVEEDORES'));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Agregar'));
    await tester.pumpAndSettle();
  }

  Future<void> add(WidgetTester tester) async {
    await menu(tester);
    final option = find.byKey(const Key('add_supplier_option'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  Future<void> pressSave(WidgetTester tester) async {
    await tester.ensureVisible(save);
    await tester.runAsync(() async {
      await tester.tap(save);
      // La transacción y su rollback usan la cola real de SQLite.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();
  }

  catalogTest(
    'crear desde Agregar, volver a proveedores, editar y consultar reactivamente',
    (tester) async {
      await pumpCatalog(tester);
      await add(tester);
      expect(find.byType(ProveedorFormScreen), findsOneWidget);
      await tester.enterText(field('name'), ' Norte ');
      await tester.enterText(field('phone'), ' 001 +52 ext. A ');
      await tester.enterText(field('notes'), ' Entrega semanal ');
      await pressSave(tester);
      expect(find.byType(InventorySuppliersTab), findsOneWidget);
      expect(find.text('Norte'), findsOneWidget);
      final base = (await read(tester)).single;
      expect(base.telefono, '001 +52 ext. A');
      expect(base.notas, 'Entrega semanal');
      await tester.tap(find.byKey(Key('supplier_${base.id}')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('name')).controller!.text,
        'Norte',
      );
      expect(
        tester.widget<TextFormField>(field('phone')).controller!.text,
        '001 +52 ext. A',
      );
      expect(
        tester.widget<TextFormField>(field('notes')).controller!.text,
        'Entrega semanal',
      );
      await tester.enterText(field('name'), ' Sur ');
      await tester.enterText(field('phone'), ' ');
      await tester.enterText(field('notes'), ' ');
      await pressSave(tester);
      expect(find.text('Sur'), findsOneWidget);
      expect(find.text('Norte'), findsNothing);
      final current = (await read(tester)).single;
      expect(current.id, base.id);
      expect(current.createdEventId, base.createdEventId);
      expect(current.telefono, isNull);
      expect(current.notas, isNull);
      expect(await h.events(), hasLength(2));
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
    },
  );

  catalogTest('nombre obligatorio y cancelar el alta no escribe', (
    tester,
  ) async {
    await pumpCatalog(tester);
    await suppliers(tester);
    expect(find.byKey(const Key('suppliers_empty')), findsOneWidget);
    await tester.tap(find.text('Añadir proveedor'));
    await tester.pumpAndSettle();
    await tester.enterText(field('name'), ' ');
    await pressSave(tester);
    expect(find.text('El nombre es obligatorio.'), findsOneWidget);
    expect(await h.events(), isEmpty);
    await tester.enterText(field('name'), 'Borrador');
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suppliers_empty')), findsOneWidget);
    expect(await h.events(), isEmpty);
    expect(await read(tester), isEmpty);
  });

  catalogTest('cancelar edición y volver atrás no persisten el borrador', (
    tester,
  ) async {
    await tester.runAsync(
      () => h.service.crearProveedor(
        const CrearProveedorCommand(nombre: 'Norte', notas: 'Inicial'),
      ),
    );
    final base = (await read(tester)).single;
    await pumpCatalog(tester);
    await suppliers(tester);
    for (final back in [false, true]) {
      await tester.tap(find.text('Norte'));
      await tester.pumpAndSettle();
      await tester.enterText(field('name'), 'Descartado');
      await tester.enterText(field('notes'), 'No guardar');
      if (back) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byTooltip('Cancelar'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Norte'), findsOneWidget);
      expect(await h.events(), hasLength(1));
      final current = (await read(tester)).single;
      expect(current.lastEventId, base.lastEventId);
      expect(current.notas, 'Inicial');
    }
  });

  catalogTest(
    'edición concurrente falla, conserva formulario y no escribe parcialmente',
    (tester) async {
      await tester.runAsync(
        () => h.service.crearProveedor(
          const CrearProveedorCommand(nombre: 'Norte'),
        ),
      );
      final base = (await read(tester)).single;
      await pumpCatalog(tester);
      await suppliers(tester);
      await tester.tap(find.text('Norte'));
      await tester.pumpAndSettle();
      await tester.enterText(field('name'), 'Mi borrador');
      await h.service.editarProveedor(
        EditarProveedorCommand(base: base, nombre: 'Otra edición'),
      );
      await pressSave(tester);
      expect(find.byType(ProveedorFormScreen), findsOneWidget);
      expect(
        find.text('El proveedor cambió desde que se abrió la edición.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(field('name')).controller!.text,
        'Mi borrador',
      );
      expect(await h.events(), hasLength(2));
      expect((await read(tester)).single.nombre, 'Otra edición');
      await tester.tap(find.byTooltip('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Otra edición'), findsOneWidget);
    },
  );

  for (final mode in AppMode.values) {
    catalogTest('disponibilidad de pestaña y menú en ${mode.name}', (
      tester,
    ) async {
      h.config.update(AppConfig.initial.copyWith(mode: mode));
      await pumpCatalog(tester);
      expect(find.text('PROVEEDORES'), findsOneWidget);
      await menu(tester);
      expect(find.byKey(const Key('add_supplier_option')), findsOneWidget);
      expect(find.byKey(const Key('add_article_option')), findsOneWidget);
      expect(find.byKey(const Key('add_category_option')), findsOneWidget);
      expect(
        find.byKey(const Key('add_inventory_resource_option')),
        findsOneWidget,
      );
      expect(await h.events(), isEmpty);
    });
  }

  catalogTest('cambio de modo conserva catálogo y menú offline', (
    tester,
  ) async {
    await pumpCatalog(tester);
    await suppliers(tester);
    await menu(tester);
    expect(find.byKey(const Key('add_supplier_option')), findsOneWidget);
    h.config.update(AppConfig.initial.copyWith(mode: AppMode.serverSync));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add_supplier_option')), findsOneWidget);
    Navigator.of(
      tester.element(find.byKey(const Key('add_article_option'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(find.text('PROVEEDORES'), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).tabs, hasLength(4));
    expect(tester.takeException(), isNull);
    expect(await h.events(), isEmpty);
  });

  catalogTest('formulario permite alta offline tras cambiar a server_sync', (
    tester,
  ) async {
    await pumpCatalog(tester);
    await add(tester);
    await tester.enterText(field('name'), 'Borrador');
    h.config.update(AppConfig.initial.copyWith(mode: AppMode.serverSync));
    await tester.pumpAndSettle();
    expect(save, findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await h.events()).single.deliveryStatus, 'pending');
    expect(await h.db.select(h.db.eventRefs).get(), hasLength(1));
  });

  catalogTest(
    'regresión de artículos, categorías y recursos junto a proveedores',
    (tester) async {
      await pumpCatalog(tester);
      expect(find.text('Café'), findsOneWidget);
      await tester.tap(find.text('CATEGORÍA'));
      await tester.pumpAndSettle();
      expect(find.text('Bebidas'), findsOneWidget);
      await tester.tap(find.text('RECURSOS'));
      await tester.pumpAndSettle();
      expect(find.text('Harina'), findsOneWidget);
      await suppliers(tester);
      expect(find.byKey(const Key('suppliers_empty')), findsOneWidget);
      await tester.tap(find.text('ARTÍCULOS'));
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsOneWidget);
      expect(await h.events(), isEmpty);
    },
  );

  catalogTest('listado transita carga, vacío, error y datos reactivos', (
    tester,
  ) async {
    final changes = StreamController<List<Proveedor>>();
    addTearDown(changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventorySuppliersTab(
            repository: _Suppliers(changes.stream),
            onOpen: (_) {},
            onAdd: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('suppliers_loading')), findsOneWidget);
    changes.add([]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suppliers_empty')), findsOneWidget);
    changes.addError(StateError('fallo de lectura'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suppliers_error')), findsOneWidget);
    changes.add([
      const Proveedor(
        id: 'supplier',
        nombre: 'Reactivo',
        version: 1,
        createdEventId: null,
        lastEventId: null,
        lastServerSequence: null,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Reactivo'), findsOneWidget);
    expect(find.byKey(const Key('suppliers_error')), findsNothing);
  });

  catalogTest(
    'guardar bloquea doble toque y cancelación, error permite reintento',
    (tester) async {
      var calls = 0;
      var pending = Completer<void>();
      Future<void> onSave(ProveedorFormResult result) {
        calls++;
        return pending.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ProveedorFormScreen(config: h.config, onSave: onSave),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(field('name'), 'Nombre');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save);
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('cancel_supplier_button')))
            .onPressed,
        isNull,
      );
      pending.completeError(StateError('fallo de prueba'));
      await tester.pumpAndSettle();
      expect(find.text('fallo de prueba'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(field('name')).controller!.text,
        'Nombre',
      );
      pending = Completer<void>();
      await tester.tap(save);
      await tester.pump();
      expect(calls, 2);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ProveedorFormScreen), findsNothing);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(740, 360),
    const Size(1280, 800),
  ]) {
    catalogTest(
      'pestañas, menú y formulario accesibles en $size con texto 1.3',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: InventoryManagementScreen(
              categoriaRepository: _Categories(),
              productoRepository: _Products(),
              proveedorRepository: h.repository,
              proveedorCommandService: h.service,
              appConfigController: h.config,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await suppliers(tester);
        expect(find.byKey(const Key('suppliers_empty')), findsOneWidget);
        await add(tester);
        await tester.enterText(field('name'), 'Adaptable');
        await tester.ensureVisible(save);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Cancelar'));
        await tester.pumpAndSettle();
        expect(await h.events(), isEmpty);
      },
    );
  }
}

class _Suppliers implements ProveedorRepository {
  _Suppliers(this.stream);
  final Stream<List<Proveedor>> stream;
  @override
  Stream<List<Proveedor>> watchProveedores() => stream;
}

class _Categories implements CategoriaRepository {
  static const rows = [
    Categoria(
      id: 'category',
      nombre: 'Bebidas',
      color: ColorCategoria.blue,
      orden: 0,
    ),
  ];
  @override
  Stream<List<Categoria>> watchCategorias() => Stream.value(rows);
  @override
  Future<List<Categoria>> obtenerCategorias() async => rows;
}

class _Products implements ProductoRepository {
  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const {},
    bool incluirSinCategoria = false,
  }) => Stream.value(const [
    ArticuloListado(
      productoId: 'product',
      nombre: 'Café',
      categoriaId: 'category',
      categoriaNombre: 'Bebidas',
      categoriaColor: ColorCategoria.blue,
      activo: true,
      variantesActivas: [
        VarianteListado(
          varianteId: 'variant',
          nombre: null,
          precioVentaMenor: 1500,
          orden: 0,
        ),
      ],
    ),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Lectura inesperada: $invocation');
}

class _Resources implements RecursoInventarioRepository {
  @override
  Stream<List<RecursoInventarioListado>> watchRecursos({
    String busqueda = '',
    InventoryResourceFilter filtro = InventoryResourceFilter.all,
  }) => Stream.value(const [
    RecursoInventarioListado(
      id: 'resource',
      nombre: 'Harina',
      activo: true,
      existenciaAtomica: 1000,
      unidadPredeterminada: UnidadInventario(
        id: 'kg',
        nombre: 'Kilogramo',
        code: 'kg',
        maximosDecimales: 3,
        simbolo: 'kg',
        factorAtomico: 1000,
        dimension: DimensionUnidad.mass,
        activa: true,
      ),
    ),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Lectura inesperada: $invocation');
}
