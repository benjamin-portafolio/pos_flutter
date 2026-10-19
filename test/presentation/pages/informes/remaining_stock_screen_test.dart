import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/informes/remaining_stock_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/reports_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/widgets/remaining_stock_report_card.dart';

import '../../../support/fake_reports_producto_repository.dart';

void main() {
  group('consulta del catálogo local desde Informes', () {
    late AppDatabase db;
    late ProductoRepositoryImpl repository;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = ProductoRepositoryImpl(productoDao: ProductoDao(db));
      await _seed(db);
    });
    tearDown(() => db.close());

    void catalogTest(String name, WidgetTesterCallback body) {
      testWidgets(name, (tester) async {
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
        }
      });
    }

    Future<void> openReports(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsScreen(
              repository: _SalesRepository(),
              productoRepository: repository,
              now: () => DateTime(2026, 9, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openStock(WidgetTester tester) async {
      await tester.tap(find.text('EXISTENCIAS RESTANTES'));
      await tester.pumpAndSettle();
    }

    catalogTest(
      'abre, cuenta variantes y filtra inactivas, recetas y sin seguimiento',
      (tester) async {
        await openReports(tester);
        expect(find.text('3 variantes con seguimiento'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        await openStock(tester);
        expect(find.byType(RemainingStockScreen), findsOneWidget);
        expect(find.text('Inventario actual'), findsOneWidget);
        // Dos variantes del mismo artículo cuentan por separado. Los saldos
        // positivos, cero y negativos se conservan con la unidad del inventario.
        expect(find.text('Aceite'), findsOneWidget);
        expect(find.text('Arroz'), findsNWidgets(2));
        expect(find.text('Integral'), findsOneWidget);
        expect(find.text('Blanco'), findsOneWidget);
        expect(find.text('−0.125 L'), findsOneWidget);
        expect(find.text('0 pza'), findsOneWidget);
        expect(find.text('2.5 kg'), findsOneWidget);
        expect(find.text('Variante sin nombre'), findsNothing);
        for (final name in [
          'Inactivo',
          'Retirada',
          'Con receta',
          'Sin control',
        ]) {
          expect(find.text(name), findsNothing);
        }
        final positions = [
          'oil-v',
          'rice-first',
          'rice-second',
        ].map((id) => tester.getTopLeft(find.byKey(ValueKey(id))).dy).toList();
        expect(positions[0], lessThan(positions[1]));
        expect(positions[1], lessThan(positions[2]));
      },
    );

    catalogTest('período y calendario no alteran el inventario actual', (
      tester,
    ) async {
      await openReports(tester);
      await tester.tap(find.byTooltip('Período anterior'));
      await tester.pumpAndSettle();
      expect(find.text('16 septiembre 2026'), findsOneWidget);
      expect(find.text('3 variantes con seguimiento'), findsOneWidget);
      await openStock(tester);
      expect(find.text('2.5 kg'), findsOneWidget);
      expect(find.text('−0.125 L'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Este mes'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Este mes'));
      await tester.pumpAndSettle();
      expect(
        find.text('1 septiembre 2026 – 30 septiembre 2026'),
        findsOneWidget,
      );
      expect(find.text('3 variantes con seguimiento'), findsOneWidget);
      await openStock(tester);
      expect(find.text('2.5 kg'), findsOneWidget);
      expect(find.text('0 pza'), findsOneWidget);
      expect(find.text('−0.125 L'), findsOneWidget);
    });

    catalogTest(
      'reacciona a saldos, nombres, seguimiento y bajas del catálogo',
      (tester) async {
        await openReports(tester);
        await openStock(tester);
        await (db.update(
          db.inventoryBalances,
        )..where((b) => b.inventoryItemId.equals('rice-second-stock'))).write(
          const InventoryBalancesCompanion(
            quantityOnHandAtomic: Value(-1234),
            quantityAvailableAtomic: Value(-1234),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('−1.234 kg'), findsOneWidget);

        await (db.update(db.products)..where((p) => p.id.equals('rice'))).write(
          const ProductsCompanion(name: Value('Arroz nuevo')),
        );
        await (db.update(
          db.productVariants,
        )..where((v) => v.id.equals('rice-second'))).write(
          const ProductVariantsCompanion(
            name: Value('Jazmín'),
            nameKey: Value('jazmín'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Arroz nuevo'), findsNWidgets(2));
        expect(find.text('Jazmín'), findsOneWidget);
        expect(find.text('Blanco'), findsNothing);

        await (db.update(
          db.productVariants,
        )..where((v) => v.id.equals('rice-second'))).write(
          const ProductVariantsCompanion(inventoryItemId: Value(null)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Jazmín'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('2 variantes con seguimiento'), findsOneWidget);

        await (db.update(
          db.productVariants,
        )..where((v) => v.id.equals('rice-second'))).write(
          const ProductVariantsCompanion(
            inventoryItemId: Value('rice-second-stock'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('3 variantes con seguimiento'), findsOneWidget);
        await openStock(tester);
        expect(find.text('Jazmín'), findsOneWidget);
        expect(find.text('−1.234 kg'), findsOneWidget);

        await (db.update(db.productVariants)
              ..where((v) => v.id.equals('rice-first')))
            .write(const ProductVariantsCompanion(active: Value(false)));
        await tester.pumpAndSettle();
        expect(find.text('Integral'), findsNothing);
        await (db.update(db.products)..where((p) => p.id.equals('rice'))).write(
          const ProductsCompanion(active: Value(false)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Arroz nuevo'), findsNothing);
        await (db.update(db.products)..where((p) => p.id.equals('oil'))).write(
          const ProductsCompanion(active: Value(false)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('No hay variantes con seguimiento de existencias.'),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('0 variantes con seguimiento'), findsOneWidget);
      },
    );
  });

  testWidgets('carga, vacío y llegada reactiva de una variante', (
    tester,
  ) async {
    final repository = FakeReportsProductoRepository(emitInitial: false);
    addTearDown(repository.controller.close);
    await tester.pumpWidget(
      MaterialApp(home: RemainingStockScreen(repository: repository)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('No hay variantes con seguimiento de existencias.'),
      findsNothing,
    );
    await tester.pump();
    repository.emit([]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('No hay variantes con seguimiento de existencias.'),
      findsOneWidget,
    );
    repository.emit([_article('nuevo')]);
    await tester.pumpAndSettle();
    expect(find.text('Artículo nuevo'), findsOneWidget);
    expect(find.text('5 pz'), findsOneWidget);
  });

  testWidgets(
    'error de listado oculta datos anteriores y reintenta la consulta',
    (tester) async {
      final repository = FakeReportsProductoRepository()
        ..articles = [_article('a')];
      addTearDown(repository.controller.close);
      await tester.pumpWidget(
        MaterialApp(home: RemainingStockScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Artículo a'), findsOneWidget);
      repository.controller.addError(StateError('Sin lectura'));
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudieron cargar las existencias.'),
        findsOneWidget,
      );
      expect(find.text('5 pz'), findsNothing);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(repository.watchCalls, 2);
      expect(find.text('5 pz'), findsOneWidget);
      expect(find.text('No se pudieron cargar las existencias.'), findsNothing);
    },
  );

  testWidgets(
    'tarjeta carga, falla y reintenta sin presentar el error como cero',
    (tester) async {
      final repository = FakeReportsProductoRepository(emitInitial: false);
      addTearDown(repository.controller.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemainingStockReportCard(repository: repository),
          ),
        ),
      );
      expect(find.text('Cargando variantes…'), findsOneWidget);
      await tester.pump();
      repository.controller.addError(StateError('Sin catálogo'));
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudieron cargar las existencias.'),
        findsOneWidget,
      );
      expect(find.text('0 variantes con seguimiento'), findsNothing);
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(repository.watchCalls, 2);
      expect(find.byType(RemainingStockScreen), findsNothing);
      repository.emit([_article('a')]);
      await tester.pumpAndSettle();
      expect(find.text('1 variante con seguimiento'), findsOneWidget);
    },
  );

  for (final size in [const Size(320, 740), const Size(1024, 768)]) {
    testWidgets(
      'lista bajo demanda sin desbordamiento en $size con texto grande',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FakeReportsProductoRepository()
          ..articles = List.generate(100, (index) => _article('$index'));
        addTearDown(repository.controller.close);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: RemainingStockScreen(repository: repository),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Artículo 0'), findsOneWidget);
        expect(find.text('Artículo 99'), findsNothing);
        expect(
          tester.widget<ListView>(find.byType(ListView)).childrenDelegate,
          isA<SliverChildBuilderDelegate>(),
        );
        await tester.scrollUntilVisible(find.text('Artículo 99'), 500);
        await tester.pumpAndSettle();
        expect(find.text('Artículo 99'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _SalesRepository implements ConfirmedSaleRepository {
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value([]);
}

ArticuloListado _article(String id) => ArticuloListado(
  productoId: id,
  nombre: 'Artículo $id',
  activo: true,
  categoriaId: null,
  categoriaNombre: null,
  categoriaColor: null,
  variantesActivas: [
    VarianteListado(
      varianteId: '$id-v',
      nombre: null,
      precioVentaMenor: 100,
      orden: 0,
      inventario: RecursoInventarioListado(
        id: '$id-stock',
        nombre: 'Recurso $id',
        activo: true,
        existenciaAtomica: 5,
        unidadPredeterminada: const UnidadInventario(
          id: InventoryUnitIds.piece,
          code: 'piece',
          nombre: 'Pieza',
          simbolo: 'pz',
          dimension: DimensionUnidad.count,
          factorAtomico: 1,
          maximosDecimales: 0,
          activa: true,
        ),
      ),
    ),
  ],
);

Future<void> _seed(AppDatabase db) async {
  for (final product in [
    ('rice', 'Arroz', true),
    ('oil', 'Aceite', true),
    ('hidden', 'Inactivo', false),
    ('recipe', 'Con receta', true),
    ('untracked', 'Sin control', true),
  ]) {
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: product.$1,
            name: product.$2,
            active: Value(product.$3),
          ),
        );
  }
  // La unidad de venta difiere de la de inventario: el informe debe usar kg.
  await (db.update(db.products)..where((p) => p.id.equals('rice'))).write(
    const ProductsCompanion(
      saleMode: Value('measured'),
      saleUnitId: Value(InventoryUnitIds.gram),
      priceReferenceQuantityAtomic: Value(100),
    ),
  );
  for (final stock in [
    ('oil-v', InventoryUnitIds.liter, -125),
    ('rice-first', InventoryUnitIds.piece, 0),
    ('rice-second', InventoryUnitIds.kilogram, 2500),
    ('hidden-v', InventoryUnitIds.piece, 90),
    ('retired', InventoryUnitIds.piece, 100),
  ]) {
    final id = '${stock.$1}-stock';
    await db
        .into(db.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            id: id,
            name: id,
            defaultUnitId: stock.$2,
          ),
        );
    await db
        .into(db.inventoryBalances)
        .insert(
          InventoryBalancesCompanion.insert(
            inventoryItemId: id,
            quantityOnHandAtomic: stock.$3,
            quantityAvailableAtomic: stock.$3,
            lastEventId: 'initial',
          ),
        );
  }
  for (final variant in [
    ('rice-second', 'rice', 'Blanco', 1, true, true),
    ('rice-first', 'rice', 'Integral', 0, true, true),
    ('oil-v', 'oil', null, 0, true, true),
    ('hidden-v', 'hidden', null, 0, true, true),
    ('retired', 'rice', 'Retirada', 2, false, true),
    ('recipe-v', 'recipe', null, 0, true, false),
    ('untracked-v', 'untracked', null, 0, true, false),
  ]) {
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: variant.$1,
            productId: variant.$2,
            name: Value(variant.$3),
            nameKey: Value(variant.$3?.toLowerCase()),
            salePriceMinor: 100,
            sortOrder: variant.$4,
            active: Value(variant.$5),
            inventoryItemId: Value(variant.$6 ? '${variant.$1}-stock' : null),
          ),
        );
  }
  await db
      .into(db.recipeComponents)
      .insert(
        RecipeComponentsCompanion.insert(
          variantId: 'recipe-v',
          inventoryItemId: 'oil-v-stock',
          quantityAtomic: 50,
        ),
      );
}
