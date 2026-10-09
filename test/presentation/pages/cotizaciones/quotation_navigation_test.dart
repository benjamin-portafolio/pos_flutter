import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/cotizacion_command_service.dart';
import 'package:pos_flutter/application/commands/cotizaciones/guardar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/domain/repositories/quotation_repository.dart';
import 'package:pos_flutter/domain/repositories/sale_draft_repository.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/models/quotation_display.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotation_detail_screen.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotation_ticket_screen.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotations_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/home_screen.dart';
import 'package:pos_flutter/presentation/tickets/ticket_image_generator.dart';

import '../../../support/pump_receipt_image.dart';
import '../../../support/quotation_harness.dart';

void main() {
  setUp(() async => getIt.reset());
  tearDown(() async => getIt.reset());

  testWidgets(
    'menú cierra drawer y recuperación/continuación regresan al único Home y Caja persistida',
    (tester) async {
      final h = _widgetHarness();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump();
        await tester.runAsync(h.dispose);
      });
      late GuardarCotizacionCommand intent;
      await tester.runAsync(() async {
        await h.seed();
        await h.add();
        await h.add(QuotationHarness.measuredId);
        intent = await h.intent();
        await h.service().guardar(intent);
        await h.drafts.limpiar(
          LimpiarVentaBorradorCommand(
            saleId: intent.saleId,
            expectedDraftEventId: intent.expectedDraftEventId,
          ),
        );
      });
      _registerHome(h);
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await _settle(tester);
      final home = tester.state(find.byType(HomeScreen));
      await _history(tester);
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isFalse,
      );
      await _tap(tester, find.text('Cotización ${intent.quotationId}'));
      await tester.ensureVisible(find.text('Recuperar en Caja'));
      await _tap(tester, find.text('Recuperar en Caja'));
      expect(find.byType(QuotationsScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.state(find.byType(HomeScreen)), same(home));
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2,
      );
      expect(find.byType(CajaScreen), findsOneWidget);
      expect(find.text('Pan · Original'), findsOneWidget);
      final recovered = (await tester.runAsync(
        () => getIt<SaleDraftRepository>().watchCurrentDraft().first,
      ))!;
      expect(recovered.id, isNot(intent.saleId));
      await tester.runAsync(
        () => h.drafts.actualizarProducto(
          ActualizarProductoBorradorCommand(
            saleItemId: recovered.items.first.id,
            quantity: 2,
          ),
        ),
      );
      await _settle(tester);
      final edited = (await tester.runAsync(
        () => getIt<SaleDraftRepository>().watchCurrentDraft().first,
      ))!;
      await tester.runAsync(() async {
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(QuotationHarness.directId))).write(
          const ProductVariantsCompanion(salePriceMinor: Value(12345)),
        );
      });
      final beforeContinue = await tester.runAsync(h.contents);
      await _history(tester);
      expect(find.textContaining('En venta'), findsOneWidget);
      await _tap(tester, find.text('Cotización ${intent.quotationId}'));
      await tester.ensureVisible(find.text('Continuar venta'));
      await _tap(tester, find.text('Continuar venta'));
      final continued = (await tester.runAsync(
        () => getIt<SaleDraftRepository>().watchCurrentDraft().first,
      ))!;
      expect(continued.id, recovered.id);
      expect(continued.lastEventId, edited.lastEventId);
      expect(continued.items.first.quantity, 2);
      expect(
        continued.items.first.unitPriceMinor,
        edited.items.first.unitPriceMinor,
      );
      expect(await tester.runAsync(h.contents), beforeContinue);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2,
      );
      expect(tester.state(find.byType(HomeScreen)), same(home));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'Caja guarda una vez y Nueva captura limpia sólo origen; historial conserva documento',
    (tester) async {
      final h = _widgetHarness();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump();
        await tester.runAsync(h.dispose);
      });
      await tester.runAsync(() async {
        await h.seed();
        await h.add();
      });
      _registerHome(h);
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await _settle(tester);
      await _tap(tester, find.text('Cotizar'));
      await pumpReceiptImage(tester);
      final ticket = tester.widget<QuotationTicketScreen>(
        find.byType(QuotationTicketScreen),
      );
      final before = (await tester.runAsync(
        () => h.repository.findById(ticket.quotationId),
      ))!;
      expect(before.sourceSaleId, ticket.emissionDraft!.saleId);
      await _tap(tester, find.text('Nueva captura'));
      expect(find.byType(QuotationTicketScreen), findsNothing);
      expect(find.text('La venta está vacía.'), findsOneWidget);
      await _history(tester);
      expect(find.textContaining('Disponible'), findsOneWidget);
      expect(find.text('Cotización ${before.id}'), findsOneWidget);
      expect(
        (await tester.runAsync(
          () => h.repository.findById(before.id),
        ))!.items.first.productName,
        'Pan',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'listado real observa cobrar y Toda permite consultar Vendida sin recuperar',
    (tester) async {
      final h = _widgetHarness();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump();
        await tester.runAsync(h.dispose);
      });
      late GuardarCotizacionCommand intent;
      await tester.runAsync(() async {
        await h.seed();
        await h.add();
        intent = await h.intent();
        await h.service().guardar(intent);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationsScreen(
            repository: h.repository,
            commands: h.service(),
          ),
        ),
      );
      await _settle(tester);
      expect(find.textContaining('En venta'), findsOneWidget);
      await tester.runAsync(() => h.confirm());
      await _settle(tester);
      expect(find.text('No hay cotizaciones recuperables.'), findsOneWidget);
      await _tap(tester, find.text('Todas'));
      expect(find.textContaining('Vendida'), findsOneWidget);
      await _tap(tester, find.text('Cotización ${intent.quotationId}'));
      expect(find.byType(QuotationDetailScreen), findsOneWidget);
      expect(find.text('Recuperar en Caja'), findsNothing);
      expect(find.text('Continuar venta'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'P09/P10/P26: listado y detalle abiertos reaccionan a precio, producto y unidad sin escribir',
    (tester) async {
      final h = _widgetHarness();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(h.dispose);
      });
      late GuardarCotizacionCommand intent;
      await tester.runAsync(() async {
        await h.seed();
        await h.add();
        await h.add(QuotationHarness.measuredId);
        intent = await h.intent();
        await h.service().guardar(intent);
      });
      final beforeRead = await tester.runAsync(
        () => h.contents(excluded: {'products', 'product_variants', 'units'}),
      );
      await tester.pumpWidget(
        MaterialApp(home: QuotationsScreen(repository: h.repository)),
      );
      await _settle(tester);
      expect(find.textContaining(r'$110.01 MXN'), findsOneWidget);
      await tester.runAsync(() async {
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(QuotationHarness.directId))).write(
          const ProductVariantsCompanion(
            salePriceMinor: Value(12000),
            standardCostMinor: Value(1500),
          ),
        );
      });
      await _settle(tester);
      final before = await tester.runAsync(h.contents);
      expect(find.textContaining(r'$195.01 MXN'), findsOneWidget);
      await _tap(tester, find.text('Cotización ${intent.quotationId}'));
      expect(find.textContaining('Fecha de creación:'), findsOneWidget);
      expect(find.textContaining('Cálculo:'), findsOneWidget);
      expect(find.text(QuotationDisplay.recoveryNotice), findsOneWidget);
      expect(await tester.runAsync(h.contents), before);
      for (final change in ['product', 'unit', 'variant']) {
        await tester.runAsync(
          () => h.db.transaction(() async {
            await (h.db.update(
              h.db.products,
            )..where((t) => t.id.equals(QuotationHarness.productId))).write(
              ProductsCompanion(
                active: Value(change != 'product'),
                name: const Value('Pan renombrado'),
              ),
            );
            await (h.db.update(h.db.units)
                  ..where((t) => t.unitId.equals(InventoryUnitIds.kilogram)))
                .write(UnitsCompanion(active: Value(change != 'unit')));
            await (h.db.update(
              h.db.productVariants,
            )..where((t) => t.id.equals(QuotationHarness.directId))).write(
              ProductVariantsCompanion(active: Value(change != 'variant')),
            );
          }),
        );
        await _settle(tester);
        final changed = await tester.runAsync(h.contents);
        expect(
          find.text('Total estimado actual: Total no disponible'),
          findsOneWidget,
        );
        expect(find.textContaining('Pan renombrado'), findsNothing);
        expect(find.textContaining('Pan'), findsOneWidget);
        expect(find.textContaining('Café medido'), findsOneWidget);
        expect(find.textContaining('Precio no disponible'), findsOneWidget);
        expect(await tester.runAsync(h.contents), changed);
        expect(
          await tester.runAsync(
            () =>
                h.contents(excluded: {'products', 'product_variants', 'units'}),
          ),
          beforeRead,
        );
      }
    },
  );

  testWidgets(
    'P10/P26/P27: dos PNG en la misma pantalla; share estable durante cambio de precio, sin escrituras',
    (tester) async {
      final h = _widgetHarness();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(h.dispose);
      });
      final output = Platform.environment['POS_QUOTATION_PNG_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final font = FontLoader('Roboto')
            ..addFont(
              File(
                '/System/Library/Fonts/Supplemental/Arial.ttf',
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await font.load();
        });
      }
      late GuardarCotizacionCommand intent;
      await tester.runAsync(() async {
        await h.seed();
        await h.add();
        await h.add();
        await h.add(QuotationHarness.measuredId);
        intent = await h.intent();
        await h.service().guardar(intent);
      });
      final before = await tester.runAsync(h.contents);
      final requests = <ShareParams>[];
      final gate = Completer<ShareResult>();
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: intent.quotationId,
            repository: h.repository,
            shareTicket: (request) {
              requests.add(request);
              return requests.length == 1
                  ? gate.future
                  : Future.value(
                      const ShareResult('', ShareResultStatus.dismissed),
                    );
            },
          ),
        ),
      );
      await _settle(tester);
      await pumpReceiptImage(tester);
      final first =
          (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes;
      expect(
        tester.widget<Image>(find.byType(Image)).semanticLabel,
        contains(r'$145.01 MXN'),
      );
      expect(await tester.runAsync(h.contents), before);
      final share = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Compartir',
      );
      final callback = tester.widget<IconButton>(share).onPressed!;
      await tester.tap(share);
      callback();
      await tester.pump();
      expect(requests, hasLength(1));
      await tester.runAsync(() async {
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(QuotationHarness.directId))).write(
          const ProductVariantsCompanion(salePriceMinor: Value(12000)),
        );
      });
      await _settle(tester);
      await pumpReceiptImage(tester);
      final changed = await tester.runAsync(h.contents);
      final preview = tester.widget<Image>(find.byType(Image));
      final second = (preview.image as MemoryImage).bytes;
      expect(preview.semanticLabel, contains(r'$315.01 MXN'));
      expect(second, isNot(first));
      expect(await requests.single.files!.single.readAsBytes(), first);
      expect(tester.widget<IconButton>(share).onPressed, isNull);
      gate.complete(const ShareResult('', ShareResultStatus.dismissed));
      await _settle(tester);
      await tester.tap(find.byTooltip('WhatsApp'));
      await _settle(tester);
      expect(requests, hasLength(2));
      expect(await requests.last.files!.single.readAsBytes(), second);
      expect(await tester.runAsync(h.contents), changed);
      if (output != null) {
        await tester.runAsync(() async {
          await Directory(output).create(recursive: true);
          await File('$output/cotizacion-precio-antes.png').writeAsBytes(first);
          await File(
            '$output/cotizacion-precio-despues.png',
          ).writeAsBytes(second);
        });
      }
    },
  );

  testWidgets(
    'reinicio real carga ticket por ID: editar captura/catalogo muestra estimación vigente',
    (tester) async {
      late Directory temp;
      late QuotationHarness h;
      late GuardarCotizacionCommand intent;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp(
          'pos_quotation_ui_restart_',
        );
      });
      addTearDown(() async {
        await h.dispose();
        await temp.delete(recursive: true);
      });
      await tester.runAsync(() async {
        h = _widgetHarness(file: File('${temp.path}/quotation.sqlite'));
        await h.seed();
        await h.add();
        await h.add(QuotationHarness.measuredId);
        intent = await h.intent();
        await h.service().guardar(intent);
      });
      final original = (await tester.runAsync(
        () => h.repository.findById(intent.quotationId),
      ))!;
      final bytes = (await tester.runAsync(
        () async => TicketImageGenerator().generate(
          QuotationDisplay(
            original,
            await h.repository.estimate(original),
          ).ticket,
        ),
      ))!;
      await tester.runAsync(() async {
        final line = (await h.db.saleDao.items(intent.saleId)).first;
        await h.drafts.actualizarProducto(
          ActualizarProductoBorradorCommand(saleItemId: line.id, quantity: 2),
        );
        await h.db.customStatement(
          'UPDATE product_variants SET sale_price_minor = 99999',
        );
        await h.dispose();
        h = _widgetHarness(file: File('${temp.path}/quotation.sqlite'));
      });
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: intent.quotationId,
            repository: h.repository,
          ),
        ),
      );
      await _settle(tester);
      await pumpReceiptImage(tester);
      final preview = tester.widget<Image>(find.byType(Image));
      expect((preview.image as MemoryImage).bytes, isNot(bytes));
      expect(preview.semanticLabel, contains(intent.quotationId));
      expect(preview.semanticLabel, contains(r'$1749.98 MXN'));
      expect(
        (await tester.runAsync(
          () => h.repository.findById(intent.quotationId),
        ))!.issuedAtLocal,
        intent.issuedAtLocal,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

void _registerHome(QuotationHarness h) {
  getIt.registerSingleton<QuotationRepository>(h.repository);
  getIt.registerSingleton<CotizacionCommandService>(h.service());
  getIt.registerSingleton<VentaBorradorCommandService>(h.drafts);
  getIt.registerSingleton<SaleDraftRepository>(
    SaleDraftRepositoryImpl(
      saleDao: h.db.saleDao,
      userId: h.context.userId,
      deviceId: h.context.deviceId,
    ),
  );
  getIt.registerSingleton<ProductoRepository>(
    ProductoRepositoryImpl(productoDao: h.db.productoDao),
  );
  getIt.registerSingleton<CategoriaRepository>(
    CategoriaRepositoryImpl(categoriaDao: h.db.categoriaDao),
  );
  getIt.registerSingleton<AppConfigController>(h.config);
}

Future<void> _history(WidgetTester tester) async {
  await _tap(tester, find.text('Artículos'));
  await _tap(tester, find.byIcon(Icons.menu));
  await tester.scrollUntilVisible(
    find.text('Cotizaciones'),
    200,
    scrollable: find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    ),
  );
  final open = tester
      .widget<ListTile>(find.widgetWithText(ListTile, 'Cotizaciones'))
      .onTap!;
  await tester.runAsync(() async {
    await tester.tap(find.text('Cotizaciones'));
    open();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await _settle(tester);
  expect(find.byType(QuotationsScreen), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pumpAndSettle();
}

QuotationHarness _widgetHarness({File? file}) => QuotationHarness(
  database: AppDatabase.forTesting(
    DatabaseConnection(
      file == null ? NativeDatabase.memory() : NativeDatabase(file),
      closeStreamsSynchronously: true,
    ),
  ),
);
