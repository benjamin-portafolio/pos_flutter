import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/presentation/pages/articulos/article_search_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';

import '../../../support/barcode_sale_fixture.dart';

void main() {
  late BarcodeSaleFixture fixture;
  late PageStorageBucket tabStorage;

  setUp(() {
    fixture = BarcodeSaleFixture();
    tabStorage = PageStorageBucket();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await fixture.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> open(WidgetTester tester, {bool physical = false}) async {
    debugDefaultTargetPlatformOverride = physical
        ? TargetPlatform.android
        : TargetPlatform.iOS;
    tester.view.physicalSize = const Size(420, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: tabStorage,
            child: CajaScreen(
              productoRepository: fixture.products,
              saleDraftRepository: fixture.drafts,
              ventaBorradorCommandService: fixture.commands,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> add(WidgetTester tester, String variant) async {
    await tester.runAsync(
      () => fixture.commands.agregar(
        AgregarProductoBorradorCommand(variantId: variant),
      ),
    );
    await settle(tester);
  }

  void tabsTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> scan(WidgetTester tester, String code) async {
    tester
            .widget<TextField>(find.byKey(const Key('physical_barcode_input')))
            .controller!
            .text =
        code;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  tabsTest(
    'dos pestañas, +, búsqueda, limpieza y cobro conservan cada compra',
    (tester) async {
      await tester.runAsync(fixture.seed);
      await open(tester);
      expect(find.text('Venta 1'), findsOneWidget);
      expect(find.text('Venta 2'), findsOneWidget);
      final firstId = fixture.drafts.selectedDraftId;
      await add(tester, 'A');
      await tester.tap(find.text('Venta 2'));
      await settle(tester);
      expect(find.text('La venta está vacía.'), findsOneWidget);
      final secondId = fixture.drafts.selectedDraftId;
      expect(secondId, isNot(firstId));

      await tester.tap(find.byType(TextField));
      await settle(tester);
      expect(find.byType(ArticleSearchScreen), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('B, \$1.00'));
      await settle(tester);
      await tester.tap(find.text('Ir a caja (1 artículo)'));
      await settle(tester);
      expect(find.text(r'Cobrar: $1.00'), findsOneWidget);
      expect(
        (await tester.runAsync(() => fixture.draft))!.items.single.variantId,
        'B',
      );

      await tester.tap(find.byTooltip('Agregar venta'));
      await settle(tester);
      expect(find.text('Venta 3'), findsOneWidget);
      await add(tester, 'C');
      expect(
        await tester.runAsync(() => fixture.drafts.watchDrafts().first),
        hasLength(3),
      );
      await tester.tap(find.text('Limpiar venta'));
      await settle(tester);
      expect(find.text('La venta está vacía.'), findsOneWidget);
      expect(
        await tester.runAsync(() => fixture.drafts.watchDrafts().first),
        hasLength(2),
      );

      await tester.tap(find.text('Venta 2'));
      await settle(tester);
      await tester.tap(find.text(r'Cobrar: $1.00'));
      await settle(tester);
      expect(
        tester
            .widget<PaymentMethodScreen>(find.byType(PaymentMethodScreen))
            .saleId,
        secondId,
      );
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.text('Venta 1'));
      await settle(tester);
      expect(fixture.drafts.selectedDraftId, firstId);
      expect(
        (await tester.runAsync(() => fixture.draft))!.items.single.variantId,
        'A',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    },
  );

  tabsTest(
    'cambiar pestaña espera el lector y la siguiente lectura usa la nueva venta',
    (tester) async {
      await tester.runAsync(fixture.seed);
      await open(tester, physical: true);
      final firstId = fixture.drafts.selectedDraftId;
      final gate = Completer<void>();
      fixture.beforeLookup = (code) async {
        if (code == '001') await gate.future;
      };
      await scan(tester, '001');
      expect(fixture.lookups, ['001']);
      await tester.tap(find.text('Venta 2'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fixture.drafts.selectedDraftId, firstId);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('sale-tab-1')))
            .onSelected,
        isNull,
      );
      gate.complete();
      await settle(tester);
      final secondId = fixture.drafts.selectedDraftId;
      expect(secondId, isNot(firstId));
      expect(find.text('La venta está vacía.'), findsOneWidget);
      await scan(tester, '002');
      await settle(tester);
      final sales = (await tester.runAsync(
        () => fixture.drafts.watchDrafts().first,
      ))!;
      expect(
        sales.singleWhere((sale) => sale.id == firstId).items.single.variantId,
        'A',
      );
      expect(
        sales.singleWhere((sale) => sale.id == secondId).items.single.variantId,
        'B',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    },
  );

  tabsTest(
    'volver a Caja conserva orden, selección y pestañas vacías de la sesión',
    (tester) async {
      await tester.runAsync(fixture.seed);
      await open(tester);
      await tester.tap(find.text('Venta 2'));
      await settle(tester);
      await add(tester, 'B');
      await tester.tap(find.text('Venta 1'));
      await settle(tester);
      await add(tester, 'A');
      await tester.tap(find.byTooltip('Agregar venta'));
      await settle(tester);
      final selected = fixture.drafts.selectedDraftId;
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await open(tester);
      expect(find.text('Venta 3'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('sale-tab-2')))
            .selected,
        isTrue,
      );
      expect(fixture.drafts.selectedDraftId, selected);
      await tester.ensureVisible(find.text('Venta 1'));
      await tester.tap(find.text('Venta 1'));
      await settle(tester);
      expect(
        (await tester.runAsync(() => fixture.draft))!.items.single.variantId,
        'A',
      );
      await tester.ensureVisible(find.text('Venta 2'));
      await tester.tap(find.text('Venta 2'));
      await settle(tester);
      expect(
        (await tester.runAsync(() => fixture.draft))!.items.single.variantId,
        'B',
      );
    },
  );

  tabsTest('reinicio recupera todas las compras pendientes sin mezclarlas', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('pos-sale-tabs-'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    await tester.runAsync(fixture.dispose);
    final file = File('${directory.path}/tabs.sqlite');
    fixture = BarcodeSaleFixture(
      database: AppDatabase.forTesting(NativeDatabase(file)),
    );
    await tester.runAsync(() async {
      await fixture.seed();
      for (final variant in ['A', 'B', 'C']) {
        fixture.drafts.selectDraft('sale-$variant');
        await fixture.commands.agregar(
          AgregarProductoBorradorCommand(variantId: variant),
        );
      }
      await fixture.dispose();
    });
    fixture = BarcodeSaleFixture(
      database: AppDatabase.forTesting(NativeDatabase(file)),
    );
    await open(tester);
    expect(find.text('Venta 3'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(find.text('Venta ${i + 1}'));
      await tester.tap(find.text('Venta ${i + 1}'));
      await settle(tester);
      final sale = (await tester.runAsync(() => fixture.draft))!;
      expect(sale.items.single.variantId, ['A', 'B', 'C'][i]);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}
