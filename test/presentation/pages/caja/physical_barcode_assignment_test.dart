import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_settings.dart';
import 'package:pos_flutter/application/weighing/scale_settings_controller.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/pages/caja/weighing/sale_weighing_dialog.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/physical_barcode_reader.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/articulos/article_search_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/inventory_barcode_assignment_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/inventory_barcode_variant_selector.dart';

import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/unidad_inventario_repository.dart';
import 'package:pos_flutter/domain/repositories/proveedor_repository.dart';
import 'package:pos_flutter/domain/repositories/recurso_inventario_repository.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';

import '../../../support/inventory_barcode_fixture.dart';
import '../../../support/fake_scale_gateway.dart';
import '../../../support/fake_scale_settings_store.dart';
import 'weighing/sale_weighing_controller_test.dart' show profile, weight;

void main() {
  late InventoryBarcodeFixture f;
  late Directory directory;
  late File file;
  late SaleDraftRepositoryImpl drafts;

  Future<void> initialize(AppMode mode) async {
    file = File('${directory.path}/${mode.name}.sqlite');
    f = InventoryBarcodeFixture(
      mode: mode,
      database: AppDatabase.forTesting(
        DatabaseConnection(
          NativeDatabase(file),
          closeStreamsSynchronously: true,
        ),
      ),
    );
    await f.seed();
    drafts = SaleDraftRepositoryImpl(
      saleDao: f.h.db.saleDao,
      userId: f.h.tracking.context.userId,
      deviceId: f.h.tracking.context.deviceId,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'caja-barcode-assignment-',
    );
    await initialize(AppMode.standalone);
  });
  tearDown(() async {
    await getIt.reset();
    debugDefaultTargetPlatformOverride = null;
    await f.h.dispose();
    await directory.delete(recursive: true);
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

  void assignmentTest(String name, Future<void> Function(WidgetTester) body) {
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

  TextField input(WidgetTester tester, {bool offstage = false}) =>
      tester.widget<TextField>(
        find.byKey(
          const Key('physical_barcode_input'),
          skipOffstage: !offstage,
        ),
      );

  Future<void> open(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.macOS,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CajaScreen(
            productoRepository: f.products,
            productoCommandService: f.commands,
            ventaBorradorCommandService: f.h.tracking.drafts,
            saleDraftRepository: drafts,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> send(
    WidgetTester tester,
    String code, {
    bool offstage = false,
  }) async {
    input(tester, offstage: offstage).controller!.text = code;
    if (offstage) {
      // Un callback tardío del campo cubierto tampoco debe admitir lecturas.
      input(tester, offstage: true).onSubmitted!(code);
    } else {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.done);
    }
    await tester.pump();
  }

  Future<void> select(WidgetTester tester, String variantId) async {
    await tester.tap(find.text('Asignar a una variante existente'));
    await settle(tester);
    expect(find.byType(InventoryBarcodeVariantSelector), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('inventory_barcode_target_$variantId')),
    );
    await settle(tester);
    expect(find.byType(InventoryBarcodeAssignmentScreen), findsOneWidget);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
    await settle(tester);
  }

  for (final fromSearch in [false, true]) {
    assignmentTest(
      'alta guarda código y agrega a la misma venta, buscador=$fromSearch',
      (tester) async {
        getIt.registerSingleton<CategoriaRepository>(
          CategoriaRepositoryImpl(categoriaDao: f.h.db.categoriaDao),
        );
        getIt.registerSingleton<UnidadInventarioRepository>(
          UnidadInventarioRepositoryImpl(unitDao: f.h.db.unitDao),
        );
        getIt.registerSingleton<ProveedorRepository>(
          ProveedorRepositoryImpl(f.h.db.proveedorDao),
        );
        getIt.registerSingleton<RecursoInventarioRepository>(
          RecursoInventarioRepositoryImpl(inventoryDao: f.h.db.inventoryDao),
        );
        getIt.registerSingleton<AppConfigController>(f.h.tracking.config);
        await open(tester);
        if (fromSearch) {
          await tester.tap(find.byType(TextField));
          await settle(tester);
        }
        await send(tester, '000987');
        await settle(tester);
        await tester.tap(find.text('Dar de alta un producto'));
        await settle(tester);
        expect(find.byType(ArticleFormScreen), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('article_name_field')),
          'Nuevo HID',
        );
        await tester.ensureVisible(
          find.byKey(const Key('article_variant_card_0')),
        );
        await tester.tap(find.byKey(const Key('article_variant_card_0')));
        await settle(tester);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const Key('variant_barcode_field')),
              )
              .controller!
              .text,
          '000987',
        );
        await tester.enterText(
          find.byKey(const Key('variant_sale_price_field')),
          '13',
        );
        await tester.tap(find.byKey(const Key('save_variant_button')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('save_article_button')));
        await settle(tester);
        expect(find.byType(ArticleFormScreen), findsNothing);
        final matches = await tester.runAsync(
          () => f.products.buscarVariantesPorCodigoBarras('000987'),
        );
        final draft = await tester.runAsync(
          () => drafts.watchCurrentDraft().first,
        );
        expect(matches!.single.nombreProducto, 'Nuevo HID');
        expect(
          draft!.items.map((item) => item.variantId),
          contains(matches.single.varianteId),
        );
        expect(draft.items, hasLength(2));
        expect(draft.totalMinor, 2300);
        expect(find.byType(ArticleSearchScreen), findsNothing);
        expect(input(tester).focusNode!.hasFocus, isTrue);
      },
    );
  }

  for (final mode in AppMode.values) {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.android,
    ]) {
      assignmentTest(
        'asigna y agrega al mismo borrador, ${mode.name}/${platform.name}',
        (tester) async {
          if (mode != AppMode.standalone) {
            await tester.runAsync(() async {
              await f.h.dispose();
              await initialize(mode);
            });
          }
          final original = (await tester.runAsync(
            () => drafts.watchCurrentDraft().first,
          ))!;
          final before = (await tester.runAsync(f.state))!;
          await open(tester, platform: platform);
          await send(tester, ' ０００４２ ');
          await settle(tester);
          expect(find.text('Código no encontrado'), findsOneWidget);
          await select(tester, f.variant('Agua', null));
          expect(find.text('Código nuevo: 00042'), findsOneWidget);
          expect(f.assignments, isEmpty);
          await confirm(tester);
          expect(input(tester).focusNode!.hasFocus, isTrue);
          expect(
            find.textContaining('Código guardado. Agregado: Agua'),
            findsOneWidget,
          );
          final sale = (await tester.runAsync(
            () => drafts.watchCurrentDraft().first,
          ))!;
          expect(sale.id, original.id);
          expect(
            sale.items.map((v) => v.variantId),
            containsAll([f.variant('Café', 'Chico'), f.variant('Agua', null)]),
          );
          expect(sale.totalMinor, original.totalMinor + 500);
          final events = (await tester.runAsync(
            () => f.h.db.select(f.h.db.events).get(),
          ))!;
          expect(events.length, f.initialEvents + 2);
          final assignment = events.singleWhere(
            (e) => e.eventType == ProductoActualizadoPayload.eventType,
          );
          expect(
            assignment.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          final refs = (await tester.runAsync(
            () => f.h.db.select(f.h.db.eventRefs).get(),
          ))!;
          expect(
            refs.where((r) => r.eventId == assignment.eventId).isEmpty,
            mode == AppMode.standalone,
          );
          final after = (await tester.runAsync(f.state))!;
          for (final table in ['inventory_balances', 'inventory_movements']) {
            expect(after[table], before[table]);
          }
          await send(tester, '00042');
          await settle(tester);
          expect(f.assignments, hasLength(1));
          expect(
            (await tester.runAsync(() => drafts.watchCurrentDraft().first))!
                .items
                .singleWhere((v) => v.variantId == f.variant('Agua', null))
                .quantity,
            2,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          await tester.runAsync(() async {
            await f.h.db.close();
            final reopened = AppDatabase.forTesting(NativeDatabase(file));
            try {
              expect(
                (await ProductoRepositoryImpl(
                  productoDao: reopened.productoDao,
                ).buscarVariantesPorCodigoBarras('00042')).single.varianteId,
                f.variant('Agua', null),
              );
              expect(
                (await reopened.select(reopened.sales).get()).single.id,
                original.id,
              );
            } finally {
              await reopened.close();
            }
          });
        },
      );
    }
  }

  for (final step in ['aviso', 'selector', 'confirmación']) {
    assignmentTest('cancelar $step conserva catálogo y venta', (tester) async {
      final before = await tester.runAsync(f.state);
      await open(tester);
      await send(tester, '00042');
      await settle(tester);
      if (step == 'selector') {
        await tester.tap(find.text('Asignar a una variante existente'));
        await settle(tester);
        await tester.pageBack();
      } else if (step == 'confirmación') {
        await select(tester, f.variant('Agua', null));
        await tester.tap(find.byTooltip('Cancelar'));
      } else {
        await tester.tap(find.text('Cancelar'));
      }
      await settle(tester);
      expect(input(tester).focusNode!.hasFocus, isTrue);
      expect(await tester.runAsync(f.state), before);
    });
  }

  for (final step in ['aviso', 'selector', 'confirmación']) {
    assignmentTest('buscador: cancelar $step conserva catálogo y venta', (
      tester,
    ) async {
      final before = await tester.runAsync(f.state);
      await open(tester);
      await tester.tap(find.byType(TextField));
      await settle(tester);
      await send(tester, '00042');
      await settle(tester);
      if (step == 'selector') {
        await tester.tap(find.text('Asignar a una variante existente'));
        await settle(tester);
        await tester.pageBack();
      } else if (step == 'confirmación') {
        await select(tester, f.variant('Agua', null));
        await tester.tap(find.byTooltip('Cancelar'));
      } else {
        await tester.tap(find.text('Cancelar'));
      }
      await settle(tester);
      expect(find.byType(ArticleSearchScreen), findsOneWidget);
      expect(find.text('Selección cancelada.'), findsOneWidget);
      expect(input(tester).focusNode!.hasFocus, isTrue);
      expect(await tester.runAsync(f.state), before);
    });
  }

  assignmentTest(
    'reemplazo explícito y código compartido conservan la variante elegida',
    (tester) async {
      await open(tester);
      await send(tester, '00042');
      await settle(tester);
      await select(tester, f.variant('Café', 'Grande'));
      expect(find.text('¿Reemplazar el código de barras?'), findsOneWidget);
      expect(find.text('Código actual: 002'), findsOneWidget);
      f.beforeAssign = () => f.assignDirect('Agua', null, '00042');
      await confirm(tester);
      expect(
        (await tester.runAsync(
          () => f.products.buscarVariantesPorCodigoBarras('002'),
        ))!,
        isEmpty,
      );
      expect(
        (await tester.runAsync(
          () => f.products.buscarVariantesPorCodigoBarras('00042'),
        ))!,
        hasLength(2),
      );
      final sale = (await tester.runAsync(
        () => drafts.watchCurrentDraft().first,
      ))!;
      expect(
        sale.items.map((v) => v.variantId),
        contains(f.variant('Café', 'Grande')),
      );
      expect(
        sale.items.map((v) => v.variantId),
        isNot(contains(f.variant('Agua', null))),
      );
    },
  );

  assignmentTest(
    'asignación pausa admisión y conserva FIFO de lecturas aceptadas',
    (tester) async {
      final query = Completer<void>();
      f.beforeLookup = () =>
          f.lookups.length == 1 ? query.future : Future.value();
      await open(tester);
      await send(tester, '00042');
      await send(tester, '001');
      query.complete();
      await settle(tester);
      await select(tester, f.variant('Agua', null));
      await send(tester, '003', offstage: true);
      expect(f.lookups, ['00042']);
      await confirm(tester);
      expect(f.lookups, ['00042', '00042', '001']);
      expect(input(tester).focusNode!.hasFocus, isTrue);
      final sale = (await tester.runAsync(
        () => drafts.watchCurrentDraft().first,
      ))!;
      expect(
        sale.items
            .singleWhere((v) => v.variantId == f.variant('Café', 'Chico'))
            .quantity,
        2,
      );
      expect(
        sale.items
            .singleWhere((v) => v.variantId == f.variant('Agua', null))
            .quantity,
        1,
      );
    },
  );

  assignmentTest('base obsoleta exige confirmar de nuevo antes de agregar', (
    tester,
  ) async {
    await open(tester);
    await send(tester, '00042');
    await settle(tester);
    await select(tester, f.variant('Agua', null));
    await tester.runAsync(() => f.assignDirect('Agua', null, '00043'));
    await confirm(tester);
    expect(find.textContaining('El artículo cambió.'), findsOneWidget);
    expect(find.text('Código actual: 00043'), findsOneWidget);
    expect(
      (await tester.runAsync(() => drafts.watchCurrentDraft().first))!.items,
      hasLength(1),
    );
    await confirm(tester);
    expect(input(tester).focusNode!.hasFocus, isTrue);
    expect(
      (await tester.runAsync(() => drafts.watchCurrentDraft().first))!.items,
      hasLength(2),
    );
  });

  assignmentTest(
    'fallo al asignar conserva selección; reintento agrega una vez',
    (tester) async {
      await open(tester);
      await send(tester, '00042');
      await settle(tester);
      await select(tester, f.variant('Agua', null));
      f.beforeAssign = () async => throw StateError('fallo de catálogo');
      await confirm(tester);
      expect(
        find.textContaining('No se pudo guardar el código.'),
        findsOneWidget,
      );
      expect(
        (await tester.runAsync(() => drafts.watchCurrentDraft().first))!.items,
        hasLength(1),
      );
      f.beforeAssign = null;
      await confirm(tester);
      expect(
        (await tester.runAsync(() => drafts.watchCurrentDraft().first))!.items,
        hasLength(2),
      );
      expect(
        (await tester.runAsync(() => f.h.db.select(f.h.db.events).get()))!,
        hasLength(f.initialEvents + 2),
      );
    },
  );

  for (final fail in [false, true]) {
    assignmentTest(
      'buscador: asignación conserva guardado y regreso solo con éxito, fallo=$fail',
      (tester) async {
        if (fail) {
          await tester.runAsync(
            () => f.h.db.customStatement(
              "CREATE TRIGGER reject_water BEFORE INSERT ON sale_items WHEN NEW.variant_id = '${f.variant('Agua', null)}' BEGIN SELECT RAISE(ABORT, 'fallo de venta'); END",
            ),
          );
        }
        final original = (await tester.runAsync(
          () => drafts.watchCurrentDraft().first,
        ))!;
        await open(tester);
        await tester.tap(find.byType(TextField));
        await settle(tester);
        await send(tester, '00042');
        await settle(tester);
        await select(tester, f.variant('Agua', null));
        await confirm(tester);
        expect(
          (await tester.runAsync(
            () => f.products.buscarVariantesPorCodigoBarras('00042'),
          ))!.single.varianteId,
          f.variant('Agua', null),
        );
        final sale = (await tester.runAsync(
          () => drafts.watchCurrentDraft().first,
        ))!;
        expect(sale.id, original.id);
        expect(sale.items, hasLength(fail ? 1 : 2));
        expect(
          find.byType(ArticleSearchScreen),
          fail ? findsOneWidget : findsNothing,
        );
        if (fail) {
          expect(
            find.textContaining('El código quedó guardado.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Reanudar lector'));
          await settle(tester);
          expect(
            (await tester.runAsync(
              () => drafts.watchCurrentDraft().first,
            ))!.items,
            hasLength(1),
          );
        }
      },
    );
  }

  assignmentTest(
    'fallo al agregar conserva código y reanuda resto sin reintentar',
    (tester) async {
      await tester.runAsync(
        () => f.h.db.customStatement(
          "CREATE TRIGGER reject_water BEFORE INSERT ON sale_items WHEN NEW.variant_id = '${f.variant('Agua', null)}' BEGIN SELECT RAISE(ABORT, 'fallo de venta'); END",
        ),
      );
      final query = Completer<void>();
      f.beforeLookup = () =>
          f.lookups.length == 1 ? query.future : Future.value();
      await open(tester);
      await send(tester, '00042');
      await send(tester, '001');
      query.complete();
      await settle(tester);
      await select(tester, f.variant('Agua', null));
      await confirm(tester);
      expect(find.textContaining('El código quedó guardado.'), findsOneWidget);
      expect(find.textContaining('Agregado: Agua'), findsNothing);
      expect(
        (await tester.runAsync(
          () => f.products.buscarVariantesPorCodigoBarras('00042'),
        ))!.single.varianteId,
        f.variant('Agua', null),
      );
      await tester.tap(find.text('Reanudar lector'));
      await settle(tester);
      final sale = (await tester.runAsync(
        () => drafts.watchCurrentDraft().first,
      ))!;
      expect(sale.items, hasLength(1));
      expect(sale.items.single.quantity, 2);
      final events = (await tester.runAsync(
        () => f.h.db.select(f.h.db.events).get(),
      ))!;
      expect(
        events.where(
          (e) => e.eventType == ProductoActualizadoPayload.eventType,
        ),
        hasLength(1),
      );
      expect(
        events.where(
          (e) => e.eventType == ProductoAgregadoBorradorPayload.eventType,
        ),
        hasLength(2),
      );
    },
  );

  assignmentTest(
    'segundo plano conserva asignación y exige reanudar antes de agregar',
    (tester) async {
      await open(tester);
      await send(tester, '00042');
      await settle(tester);
      await select(tester, f.variant('Agua', null));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await confirm(tester);
      expect(
        (await tester.runAsync(
          () => f.products.buscarVariantesPorCodigoBarras('00042'),
        ))!.single.varianteId,
        f.variant('Agua', null),
      );
      expect(
        (await tester.runAsync(() => drafts.watchCurrentDraft().first))!.items,
        hasLength(1),
      );
      expect(find.textContaining('Lector en pausa'), findsOneWidget);
      await tester.tap(find.text('Reanudar lector'));
      await settle(tester);
      expect(
        (await tester.runAsync(() => drafts.watchCurrentDraft().first))!.items,
        hasLength(2),
      );
      expect(input(tester).focusNode!.hasFocus, isTrue);
    },
  );

  assignmentTest('salir espera asignación y agregado antes de liberar Caja', (
    tester,
  ) async {
    await open(tester);
    await send(tester, '00042');
    await settle(tester);
    await select(tester, f.variant('Agua', null));
    var left = false;
    final caja = tester.state<CajaScreenState>(
      find.byType(CajaScreen, skipOffstage: false),
    );
    final leave = caja.prepareToLeave().then((value) => left = value);
    await tester.pump();
    expect(left, isFalse);
    expect(find.text('Finalizando lecturas…'), findsNothing);
    await confirm(tester);
    await leave;
    expect(left, isTrue);
    expect(
      (await tester.runAsync(() => drafts.watchCurrentDraft().first))!.items,
      hasLength(2),
    );
    expect(
      tester
          .state<PhysicalBarcodeReaderState>(find.byType(PhysicalBarcodeReader))
          .isEnabled,
      isFalse,
    );
  });

  for (final scenario in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    final cancel = scenario.$1;
    final weighed = scenario.$2;
    assignmentTest(
      'cantidad medida después de asignar, cancelar=$cancel, pesaje=$weighed',
      (tester) async {
        final resources = (await tester.runAsync(() async {
          final gateway = FakeScaleGateway();
          final service = ScaleSessionService(
            gateway,
            now: () => Duration.zero,
          );
          final settings = ScaleSettingsController(
            FakeScaleSettingsStore()
              ..settings = ScaleSettings(
                profiles: [profile],
                defaultId: profile.id,
              ),
            sessionService: () => service,
          );
          await settings.load();
          return (gateway, service, settings);
        }))!;
        final (gateway, service, settings) = resources;
        if (weighed) {
          getIt.registerSingleton<ScaleSettingsController>(settings);
          getIt.registerSingleton<ScaleSessionService>(service);
        }
        addTearDown(() async {
          for (final read in gateway.reads) {
            if (!read.isCompleted) read.complete([]);
          }
          await service.dispose();
          await settings.dispose();
        });
        await tester.runAsync(
          () => f.h.commands.crearArticulo(
            CrearArticuloCommand.conVariantes(
              nombre: 'A granel',
              saleConfiguration: MeasuredSaleConfiguration(
                saleUnitId: InventoryUnitIds.kilogram,
                priceReferenceQuantityAtomic: 1000,
              ),
              variantes: [
                const CrearArticuloVarianteCommand(
                  nombre: null,
                  costoEstandar: null,
                  precioVenta: '20',
                ),
              ],
            ),
          ),
        );
        final measured =
            (await tester.runAsync(
                  () => f.h.repository.watchArticulos().first,
                ))!
                .singleWhere((a) => a.nombre == 'A granel')
                .variantesActivas
                .single
                .varianteId;
        await open(
          tester,
          platform: weighed ? TargetPlatform.windows : TargetPlatform.macOS,
        );
        await send(tester, '00042');
        await settle(tester);
        await select(tester, measured);
        await confirm(tester);
        expect(
          find.byType(weighed ? SaleWeighingDialog : SaleQuantityDialog),
          findsOneWidget,
        );
        if (weighed) {
          gateway.reads.last.complete([weight(750)]);
          await settle(tester);
        } else if (!cancel) {
          await tester.enterText(
            find.byKey(const ValueKey('sale-measured-quantity')),
            '0.750',
          );
          await tester.pump();
        }
        await tester.tap(
          find.text(
            cancel
                ? 'Cancelar'
                : weighed
                ? 'Aceptar'
                : 'Agregar',
          ),
        );
        for (final read in gateway.reads) {
          if (!read.isCompleted) read.complete([]);
        }
        await settle(tester);
        expect(service.active, isNull);
        expect(input(tester).focusNode!.hasFocus, isTrue);
        expect(
          (await tester.runAsync(
            () => f.products.buscarVariantesPorCodigoBarras('00042'),
          ))!.single.varianteId,
          measured,
        );
        final sale = (await tester.runAsync(
          () => drafts.watchCurrentDraft().first,
        ))!;
        expect(sale.items, hasLength(cancel ? 1 : 2));
        if (cancel) {
          expect(
            find.text('Código guardado. Cantidad cancelada.'),
            findsOneWidget,
          );
        } else {
          expect(
            sale.items
                .singleWhere((v) => v.variantId == measured)
                .measuredQuantityAtomic,
            750,
          );
          expect(sale.totalMinor, 2500);
        }
      },
    );
  }
}
