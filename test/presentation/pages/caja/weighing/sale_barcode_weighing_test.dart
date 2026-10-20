import 'dart:async';
import 'dart:convert';
import 'package:pos_flutter/application/sync/models/sync_event.dart';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/weighing/scale_exception.dart';
import 'package:pos_flutter/application/weighing/scale_failure.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_settings.dart';
import 'package:pos_flutter/application/weighing/scale_settings_controller.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/ventas/measured_sale_conditions.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_product_selection_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/physical_barcode_reader.dart';
import 'package:pos_flutter/presentation/pages/caja/weighing/sale_barcode_quantity_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/weighing/sale_weighing_dialog.dart';

import '../../../../support/barcode_sale_fixture.dart';
import '../../../../support/fake_scale_gateway.dart';
import '../../../../support/fake_scale_settings_store.dart';
import '../physical_barcode_reader_test.dart'
    show settle, field, send, focusWindow;
import 'sale_weighing_controller_test.dart' show profile, weight;

void main() {
  late BarcodeSaleFixture f;
  late FakeScaleGateway gateway;
  late ScaleSessionService service;
  late ScaleSettingsController settings;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    f = BarcodeSaleFixture();
    await f.seed();
    gateway = FakeScaleGateway();
    service = ScaleSessionService(gateway, now: () => Duration.zero);
    final store = FakeScaleSettingsStore()
      ..settings = ScaleSettings(profiles: [profile], defaultId: profile.id);
    settings = ScaleSettingsController(store, sessionService: () => service);
    await settings.load();
    getIt.registerSingleton<ScaleSettingsController>(settings);
    getIt.registerSingleton<ScaleSessionService>(service);
  });

  tearDown(() async {
    for (final read in gateway.reads) {
      if (!read.isCompleted) read.complete([]);
    }
    if (gateway.pendingClose?.isCompleted == false) {
      gateway.pendingClose!.complete();
    }
    await service.dispose();
    await settings.dispose();
    await getIt.reset();
    await f.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalBarcodeReader(
            coordinator: f.coordinator,
            saleDraftRepository: f.drafts,
            productoRepository: f.products,
            assignBarcode: (_) async => throw UnimplementedError(),
            automaticallyEnabled: true,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> drain(WidgetTester tester) async {
    for (final read in gateway.reads) {
      if (!read.isCompleted) read.complete([]);
    }
    if (gateway.pendingOpen?.isCompleted == false) {
      gateway.pendingOpen!.complete();
    }
    await settle(tester);
  }

  Future<void> read(WidgetTester tester, [int grams = 430]) async {
    gateway.reads.last.complete([weight(grams)]);
    await settle(tester);
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.text('Cancelar').last);
    await drain(tester);
  }

  void integrationTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        for (final read in gateway.reads) {
          if (!read.isCompleted) read.complete([]);
        }
        if (gateway.pendingOpen?.isCompleted == false) {
          gateway.pendingOpen!.complete();
        }
        if (gateway.pendingClose?.isCompleted == false) {
          gateway.pendingClose!.complete();
        }
        final closing = service.active?.close();
        await settle(tester);
        await closing;
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final mode in AppMode.values) {
    integrationTest(
      '${mode.name}: HID suffix, deliberate Enter, one persisted event and replay',
      (tester) async {
        f.config.update(f.config.config.copyWith(mode: mode));
        await open(tester);
        field(tester).controller!.text = '004';
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester);
        expect(find.byType(SaleWeighingDialog), findsOneWidget);
        await read(tester);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        expect(f.attempts, isEmpty);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await drain(tester);
        expect(f.attempts, hasLength(1));
        expect(service.active, isNull);
        final draft = (await tester.runAsync(() => f.draft))!;
        expect(draft.items.single.measuredQuantityAtomic, 430);
        expect(draft.totalMinor, 8600);
        final events = (await tester.runAsync(
          () => f.db.select(f.db.events).get(),
        ))!;
        expect(events, hasLength(1));
        expect(events.single.deliveryStatus, 'not_required');
        expect(
          await tester.runAsync(() => f.db.select(f.db.eventRefs).get()),
          mode == AppMode.standalone ? isEmpty : isNotEmpty,
        );
        final stored = events.single;
        // Reapply through the existing processor; no second line or quantity.
        await tester.runAsync(
          () => f.processor.apply(
            SyncEvent(
              eventId: stored.eventId,
              aggregateType: stored.aggregateType,
              aggregateId: stored.aggregateId,
              eventType: stored.eventType,
              deviceId: stored.deviceId,
              userId: stored.userId,
              createdAtLocal: stored.createdAtLocal,
              deliveryStatus: stored.deliveryStatus,
              baseVersion: stored.baseVersion,
              payload: (jsonDecode(stored.payload) as Map)
                  .cast<String, Object?>(),
            ),
          ),
        );
        expect(
          (await tester.runAsync(
            () => f.draft,
          ))!.items.single.measuredQuantityAtomic,
          430,
        );
        expect((await tester.runAsync(() => f.draft))!.id, draft.id);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  integrationTest(
    'HID queue waits for native release; barcode burst cannot accept weight',
    (tester) async {
      final lookup = Completer<void>();
      f.beforeLookup = (code) async {
        if (code == '004') await lookup.future;
      };
      await open(tester);
      await send(tester, '004');
      await send(tester, '001');
      lookup.complete();
      await settle(tester);
      await read(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0, character: '0');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(f.attempts, isEmpty);
      gateway.pendingClose = Completer<void>();
      await tester.tap(find.text('Aceptar'));
      await settle(tester);
      expect(f.lookups, ['004']);
      expect(f.attempts, isEmpty);
      gateway.pendingClose!.complete();
      await drain(tester);
      expect(f.attempts.map((c) => c.variantId), ['M', 'A']);
      expect(service.active, isNull);
      expect(field(tester).focusNode!.hasFocus, isTrue);
      expect((await tester.runAsync(() => f.draft))!.items, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  integrationTest(
    'cancel while connecting writes nothing and releases before returning',
    (tester) async {
      gateway.pendingOpen = Completer<void>();
      await open(tester);
      await send(tester, '004');
      await settle(tester);
      await cancel(tester);
      expect(service.active, isNull);
      await tester.runAsync(f.expectNoWrites);
      await tester.pumpWidget(const SizedBox());
    },
  );

  integrationTest(
    'focus loss pauses reader and weighing; explicit resume needs fresh sample',
    (tester) async {
      await open(tester);
      await send(tester, '004');
      await settle(tester);
      await read(tester);
      focusWindow(tester, false);
      await drain(tester);
      focusWindow(tester, true);
      await settle(tester);
      expect(find.text('Reanudar'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(f.attempts, isEmpty);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reanudar').last);
      await settle(tester);
      expect(find.textContaining('Peso: 0.43'), findsNothing);
      await cancel(tester);
      await tester.runAsync(f.expectNoWrites);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final change in ['precio', 'referencia', 'unidad', 'modo', 'guardado']) {
    integrationTest(
      '$change rejects acceptance without automatic retry or reused weight',
      (tester) async {
        await open(tester);
        await send(tester, '004');
        await settle(tester);
        await read(tester);
        await tester.runAsync(() async {
          if (change == 'precio') {
            await (f.db.update(
              f.db.productVariants,
            )..where((v) => v.id.equals('M'))).write(
              const ProductVariantsCompanion(salePriceMinor: Value(100)),
            );
          } else if (change == 'guardado') {
            f.beforeSave = (_) async => throw StateError('Error de prueba');
          } else {
            await (f.db.update(
              f.db.products,
            )..where((p) => p.id.equals('product-M'))).write(
              ProductsCompanion(
                priceReferenceQuantityAtomic: change == 'modo'
                    ? const Value(null)
                    : change == 'referencia'
                    ? const Value(100)
                    : const Value.absent(),
                saleUnitId: change == 'modo'
                    ? const Value(null)
                    : change == 'unidad'
                    ? const Value(InventoryUnitIds.gram)
                    : const Value.absent(),
                saleMode: change == 'modo'
                    ? const Value('unit')
                    : const Value.absent(),
              ),
            );
          }
        });
        await tester.tap(find.text('Aceptar'));
        await drain(tester);
        expect(f.attempts, hasLength(1));
        expect(service.active, isNull);
        await tester.runAsync(f.expectNoWrites);
        await tester.pump(const Duration(seconds: 3));
        expect(f.attempts, hasLength(1));
        expect(find.textContaining('no se reintentará'), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  integrationTest('ambiguous code selects variant before connecting', (
    tester,
  ) async {
    await tester.runAsync(
      () => (f.db.update(f.db.productVariants)..where((v) => v.id.equals('M')))
          .write(const ProductVariantsCompanion(barcode: Value('003'))),
    );
    await open(tester);
    await send(tester, '003');
    await settle(tester);
    expect(find.byType(BarcodeProductSelectionDialog), findsOneWidget);
    expect(gateway.calls, isEmpty);
    await tester.tap(find.text('M').last);
    await settle(tester);
    expect(find.byType(SaleWeighingDialog), findsOneWidget);
    await cancel(tester);
    await tester.runAsync(f.expectNoWrites);
    await tester.pumpWidget(const SizedBox());
  });

  for (final route in [
    'sin predeterminada',
    'sin transporte',
    'camara',
    'volumen',
    'piezas',
  ]) {
    integrationTest('$route preserves manual/unit flow without opening scale', (
      tester,
    ) async {
      if (route == 'sin predeterminada') {
        await tester.runAsync(() => settings.setDefault(null));
      }
      if (route == 'sin transporte') {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
      }
      if (route == 'volumen') {
        await tester.runAsync(
          () =>
              (f.db.update(
                f.db.products,
              )..where((p) => p.id.equals('product-M'))).write(
                const ProductsCompanion(
                  saleUnitId: Value(InventoryUnitIds.liter),
                ),
              ),
        );
      }
      if (route == 'camara') {
        await tester.pumpWidget(
          MaterialApp(
            home: SaleBarcodeQuantityDialog(
              physicalReader: false,
              loadConditions: () => f.coordinator.conditionsFor('M'),
              watchDraft: f.drafts.watchCurrentDraft,
            ),
          ),
        );
        await settle(tester);
      } else {
        await open(tester);
        await send(tester, route == 'piezas' ? '001' : '004');
        await settle(tester);
      }
      expect(gateway.calls, isEmpty);
      expect(find.byType(SaleWeighingDialog), findsNothing);
      if (route == 'piezas') {
        expect(f.attempts, hasLength(1));
      } else {
        expect(find.byType(SaleQuantityDialog), findsOneWidget);
        if (route != 'camara') await cancel(tester);
        await tester.runAsync(f.expectNoWrites);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final gramsUnit in [false, true]) {
    integrationTest(
      'two fresh captures accumulate in same draft, grams=$gramsUnit',
      (tester) async {
        if (gramsUnit) {
          await tester.runAsync(() async {
            await (f.db.update(
              f.db.products,
            )..where((p) => p.id.equals('product-M'))).write(
              const ProductsCompanion(
                saleUnitId: Value(InventoryUnitIds.gram),
                priceReferenceQuantityAtomic: Value(100),
              ),
            );
            await (f.db.update(
              f.db.productVariants,
            )..where((v) => v.id.equals('M'))).write(
              const ProductVariantsCompanion(salePriceMinor: Value(1200)),
            );
          });
        }
        await open(tester);
        String? saleId;
        for (var i = 1; i <= 2; i++) {
          await send(tester, '004');
          await settle(tester);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Aceptar'),
                )
                .onPressed,
            isNull,
          );
          expect(f.attempts, hasLength(i - 1));
          await read(tester, gramsUnit ? 150 : 430);
          await tester.tap(find.text('Aceptar'));
          await drain(tester);
          final draft = (await tester.runAsync(() => f.draft))!;
          saleId ??= draft.id;
          expect(draft.id, saleId);
          expect(
            draft.items.single.measuredQuantityAtomic,
            (gramsUnit ? 150 : 430) * i,
          );
          expect(draft.totalMinor, (gramsUnit ? 1800 : 8600) * i);
          expect(service.active, isNull);
        }
        expect(gateway.calls.where((c) => c.startsWith('open:')), hasLength(2));
      },
    );
  }

  integrationTest('focus lost during catalog load requires explicit resume', (
    tester,
  ) async {
    final conditions = await tester.runAsync(
      () => f.coordinator.conditionsFor('M'),
    );
    final pending = Completer<MeasuredSaleConditions?>();
    await tester.pumpWidget(
      MaterialApp(
        home: SaleBarcodeQuantityDialog(
          physicalReader: true,
          loadConditions: () => pending.future,
          watchDraft: f.drafts.watchCurrentDraft,
        ),
      ),
    );
    focusWindow(tester, false);
    focusWindow(tester, true);
    pending.complete(conditions);
    await settle(tester);
    expect(gateway.calls, isEmpty);
    expect(find.text('Reanudar'), findsOneWidget);
  });

  integrationTest(
    'connection error offers retry, manual and cancel; manual starts empty after release',
    (tester) async {
      gateway.pendingOpen = Completer<void>();
      await open(tester);
      await send(tester, '004');
      await settle(tester);
      gateway.pendingOpen!.completeError(
        const ScaleException(ScaleFailure.deviceNotFound),
      );
      await settle(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      gateway.pendingOpen = null;
      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      expect(gateway.calls.where((c) => c.startsWith('open:')), hasLength(2));
      await read(tester);
      await tester.tap(find.text('Captura manual'));
      await drain(tester);
      expect(service.active, isNull);
      expect(find.byType(SaleQuantityDialog), findsOneWidget);
      expect(
        tester
            .widgetList<TextField>(
              find.descendant(
                of: find.byType(SaleQuantityDialog),
                matching: find.byType(TextField),
              ),
            )
            .every((f) => f.controller!.text.isEmpty),
        isTrue,
      );
      await cancel(tester);
      await tester.runAsync(f.expectNoWrites);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
