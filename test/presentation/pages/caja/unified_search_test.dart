import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/presentation/pages/articulos/article_search_screen.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';

import '../../../support/barcode_sale_fixture.dart';
import 'physical_barcode_reader_test.dart' show field, settle, send;

void main() {
  late BarcodeSaleFixture f;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('unified-search-');
    f = BarcodeSaleFixture(
      database: AppDatabase.forTesting(
        DatabaseConnection(
          NativeDatabase(File('${directory.path}/test.sqlite')),
          closeStreamsSynchronously: true,
        ),
      ),
    );
    await f.seed();
    for (final entry in [('A', 'Pan'), ('B', 'Leche'), ('C', '12345')]) {
      await (f.db.update(f.db.products)
            ..where((p) => p.id.equals('product-${entry.$1}')))
          .write(ProductsCompanion(name: Value(entry.$2)));
    }
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await f.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CajaScreen(
            productoRepository: f.products,
            saleDraftRepository: f.drafts,
            ventaBorradorCommandService: f.commands,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(TextField));
    await settle(tester);
    expect(find.byType(ArticleSearchScreen), findsOneWidget);
  }

  searchTest(
    'campo único, foco sin navegación, nombre, selección y código con ceros',
    (tester) async {
      await pump(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(field(tester).focusNode!.hasFocus, isTrue);
      expect(find.byType(ArticleSearchScreen), findsNothing);
      field(tester).controller!.text = 'pan';
      await open(tester);
      expect(field(tester).controller!.text, 'pan');
      expect(find.text('Pan'), findsOneWidget);
      await tester.tap(find.byType(Card));
      await settle(tester);
      expect(find.byType(ArticleSearchScreen), findsOneWidget);
      expect(f.attempts.single.variantId, 'A');
      // La selección conserva la búsqueda y el agregado por código la cierra.
      await send(tester, '002');
      await settle(tester);
      expect(find.byType(ArticleSearchScreen), findsNothing);
      expect(f.lookups.last, '002');
      expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
      expect((await tester.runAsync(() => f.draft))!.items, hasLength(2));
      expect(field(tester).focusNode!.hasFocus, isTrue);
      await send(tester, '001');
      await settle(tester);
      expect(f.attempts.map((c) => c.variantId), ['A', 'B', 'A']);
    },
  );

  searchTest(
    'parcial y nombre numérico conservan resultados; exacto tiene prioridad',
    (tester) async {
      await pump(tester);
      await open(tester);
      await tester.enterText(find.byType(TextField), '00');
      await settle(tester);
      expect(find.text('Pan'), findsOneWidget);
      expect(find.text('Leche'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(f.attempts, isEmpty);
      await send(tester, '12345');
      await settle(tester);
      expect(find.text('12345'), findsWidgets);
      expect(f.attempts, isEmpty);
      await send(tester, 'pan');
      await settle(tester);
      expect(f.attempts, isEmpty);
      await tester.runAsync(() async {
        await (f.db.update(f.db.products)
              ..where((p) => p.id.equals('product-B')))
            .write(const ProductsCompanion(name: Value('001')));
      });
      await settle(tester);
      await send(tester, '001');
      await settle(tester);
      expect(f.attempts.single.variantId, 'A');
      expect(find.byType(ArticleSearchScreen), findsNothing);
    },
  );

  for (final upper in [true, false]) {
    searchTest(
      'regreso ${upper ? 'superior' : 'inferior'} conserva Caja y venta',
      (tester) async {
        await pump(tester);
        final caja = tester.state(find.byType(CajaScreen));
        await send(tester, '001');
        await settle(tester);
        final saleId = (await tester.runAsync(() => f.draft))!.id;
        await open(tester);
        await tester.tap(
          upper ? find.byType(BackButton) : find.textContaining('Ir a caja'),
        );
        await settle(tester);
        expect(find.byType(ArticleSearchScreen), findsNothing);
        expect(identical(caja, tester.state(find.byType(CajaScreen))), isTrue);
        expect((await tester.runAsync(() => f.draft))!.id, saleId);
        expect(field(tester).focusNode!.hasFocus, isTrue);
      },
    );
  }

  searchTest('cancelar selector y cantidad mantiene búsqueda e informa', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    await send(tester, '003');
    await settle(tester);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(find.text('Selección cancelada.'), findsOneWidget);
    await send(tester, '004');
    await settle(tester);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(find.text('Cantidad cancelada.'), findsOneWidget);
    expect(find.byType(ArticleSearchScreen), findsOneWidget);
    expect(f.attempts, isEmpty);
  });

  searchTest(
    'error no regresa ni reintenta; siguiente lectura requiere reanudar',
    (tester) async {
      await pump(tester);
      await open(tester);
      f.beforeSave = (_) async => throw StateError('fallo controlado');
      await send(tester, '001');
      await settle(tester);
      expect(find.byType(ArticleSearchScreen), findsOneWidget);
      expect(find.textContaining('fallo controlado'), findsOneWidget);
      expect(f.attempts, hasLength(1));
      f.beforeSave = null;
      await tester.tap(find.text('Reanudar lector'));
      await settle(tester);
      await send(tester, '002');
      await settle(tester);
      expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
      expect(find.byType(ArticleSearchScreen), findsNothing);
    },
  );

  searchTest(
    'seleccionar coincidencia parcial agrega y permanece en búsqueda',
    (tester) async {
      await pump(tester);
      await open(tester);
      await tester.enterText(find.byType(TextField), '00');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('A')));
      await settle(tester);
      expect(f.attempts.single.variantId, 'A');
      expect(find.byType(ArticleSearchScreen), findsOneWidget);
      expect(field(tester).controller!.text, '00');
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    searchTest(
      'agregado manual conserva campo y posición de resultados en $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await pump(tester);
        // Mantener visible el pie de venta desde antes del clic.
        await send(tester, '001');
        await settle(tester);
        await open(tester);
        await tester.enterText(find.byType(TextField), '00');
        await settle(tester);
        await tester.tap(
          find.text('Buscar artículos'),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(field(tester).focusNode!.hasFocus, isTrue);
        expect(find.textContaining('Lector en pausa'), findsNothing);
        final input = find.byKey(const Key('physical_barcode_input'));
        final inputState = tester.state(input);
        final inputPosition = tester.getTopLeft(input);
        final product = find.byKey(const ValueKey('A'));
        final productPosition = tester.getTopLeft(product);
        final gate = Completer<void>();
        f.beforeSave = (_) => gate.future;

        await tester.tap(product, kind: PointerDeviceKind.mouse);
        await settle(tester);
        expect(input, findsOneWidget);
        expect(identical(inputState, tester.state(input)), isTrue);
        expect(tester.getTopLeft(input), inputPosition);
        expect(tester.getTopLeft(product), productPosition);
        expect(field(tester).controller!.text, '00');
        expect(field(tester).readOnly, isTrue);
        expect(field(tester).focusNode!.hasFocus, isTrue);
        expect(find.textContaining('Lector en pausa'), findsNothing);

        gate.complete();
        for (var frame = 0; frame < 12; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(input, findsOneWidget);
          expect(identical(inputState, tester.state(input)), isTrue);
          expect(tester.getTopLeft(product), productPosition);
          expect(field(tester).focusNode!.hasFocus, isTrue);
          expect(find.textContaining('Lector en pausa'), findsNothing);
        }
        await settle(tester);
        expect(f.attempts.map((c) => c.variantId), ['A', 'A']);
        expect(field(tester).readOnly, isFalse);
        expect(field(tester).focusNode!.hasFocus, isTrue);
        expect(field(tester).controller!.text, '00');
        expect(field(tester).keyboardType, TextInputType.text);

        await tester.tap(input, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(
          field(tester).controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 2),
        );
        await tester.enterText(input, 'leche');
        await settle(tester);
        expect(find.text('Leche'), findsOneWidget);
        expect(find.text('Pan'), findsNothing);
        // Otro clic con el campo ya enfocado también selecciona todo.
        field(tester).controller!.selection = const TextSelection.collapsed(
          offset: 2,
        );
        await tester.tap(input, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(
          field(tester).controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );
      },
    );
  }

  searchTest(
    'cantidad manual toma el foco y cancelar lo devuelve al buscador',
    (tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(
        find.byKey(const ValueKey('M')),
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);
      expect(find.byType(SaleQuantityDialog), findsOneWidget);
      expect(field(tester).focusNode!.hasFocus, isFalse);
      final dialogInputs = tester.widgetList<EditableText>(
        find.descendant(
          of: find.byType(SaleQuantityDialog),
          matching: find.byType(EditableText),
        ),
      );
      expect(dialogInputs.any((input) => input.focusNode.hasFocus), isTrue);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(field(tester).focusNode!.hasFocus, isTrue);
      expect(find.textContaining('Lector en pausa'), findsNothing);
      expect(f.attempts, isEmpty);
    },
  );

  searchTest('agregado manual respeta pausa al cambiar de aplicación', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    final gate = Completer<void>();
    f.beforeSave = (_) => gate.future;
    await tester.tap(
      find.byKey(const ValueKey('A')),
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    gate.complete();
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.textContaining('Lector en pausa'), findsOneWidget);
    expect(find.text('Reanudar lector'), findsOneWidget);
    await send(tester, '002');
    await settle(tester);
    expect(f.attempts.map((c) => c.variantId), ['A']);
    await tester.tap(find.text('Reanudar lector'));
    await settle(tester);
    await send(tester, '002');
    await settle(tester);
    expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
  });

  searchTest(
    'guardado en segundo plano espera reanudación explícita antes de regresar',
    (tester) async {
      await pump(tester);
      await open(tester);
      final gate = Completer<void>();
      f.beforeSave = (_) => gate.future;
      await send(tester, '001');
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      gate.complete();
      await settle(tester);
      expect(find.byType(ArticleSearchScreen), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(find.byType(ArticleSearchScreen), findsOneWidget);
      await tester.tap(find.text('Reanudar lector'));
      await settle(tester);
      expect(find.byType(ArticleSearchScreen), findsNothing);
      expect(f.attempts, hasLength(1));
      expect(field(tester).focusNode!.hasFocus, isFalse);
      await tester.tap(find.text('Reanudar lector'));
      await settle(tester);
      expect(field(tester).focusNode!.hasFocus, isTrue);
    },
  );

  searchTest('regreso automático espera todas las lecturas consecutivas', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    final gate = Completer<void>();
    f.beforeSave = (_) => f.attempts.length == 1 ? gate.future : Future.value();
    await send(tester, '001');
    await settle(tester);
    await send(tester, '002');
    expect(find.byType(ArticleSearchScreen), findsOneWidget);
    gate.complete();
    await settle(tester);
    expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
    expect(find.byType(ArticleSearchScreen), findsNothing);
    expect(field(tester).focusNode!.hasFocus, isTrue);
  });

  searchTest('regreso espera cola aceptada y conserva orden', (tester) async {
    await pump(tester);
    await open(tester);
    final gate = Completer<void>();
    f.beforeSave = (_) => f.attempts.length == 1 ? gate.future : Future.value();
    await send(tester, '001');
    await settle(tester);
    await send(tester, '002');
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.byType(ArticleSearchScreen), findsOneWidget);
    if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
      await tester.tap(find.text('Reanudar pendientes'));
    }
    gate.complete();
    await settle(tester);
    expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
    expect(find.byType(ArticleSearchScreen), findsNothing);
    expect(field(tester).focusNode!.hasFocus, isTrue);
  });
}

void searchTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
