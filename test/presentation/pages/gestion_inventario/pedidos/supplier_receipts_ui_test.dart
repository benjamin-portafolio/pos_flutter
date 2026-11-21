import 'package:pos_flutter/application/sync/payloads/supplier_order_draft_saved_payload.dart';
import 'package:pos_flutter/application/tickets/supplier_document_ticket.dart';
import 'package:pos_flutter/presentation/tickets/ticket_image_generator.dart';
import 'package:flutter/services.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_order_forms.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/proveedores/confirm_supplier_receipt_command.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/proveedores/supplier_order_reader.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_order_command_service.dart';
import 'package:pos_flutter/application/sync/projections/supplier_order_projection_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/domain/repositories/supplier_order_repository.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_orders_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_order_detail_screen.dart';
import '../../../../support/product_supplier_harness.dart';
import '../../../../support/supplier_order_harness.dart';
import '../../../../application/commands/proveedores/supplier_receipt_local_test.dart'
    show confirmedOrder, receipt;

Future<void> tap(WidgetTester t, String text) async {
  final matches = find.text(text);
  if (matches.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      matches,
      250,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
  }
  final f = matches.last;
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void register(ProductSupplierHarness h) {
  final repo = DriftSupplierOrderRepository(h.db);
  getIt.registerSingleton<SupplierOrderRepository>(repo);
  getIt.registerSingleton<SupplierOrderReader>(repo);
  getIt.registerSingleton<SupplierOrderProjectionStore>(h.tracking.orders);
  getIt.registerSingleton<SupplierOrderCommandService>(h.orders);
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['POS_S5_VISUAL_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _LostResponse extends SupplierOrderCommandService {
  _LostResponse(ProductSupplierHarness h)
    : super(
        store: h.tracking.orders,
        events: h.tracking.events,
        context: h.tracking.context,
        requireCompatible: () async {},
      );
  bool first = true;
  @override
  Future<void> receive(ConfirmSupplierReceiptCommand c) async {
    await super.receive(c);
    if (first) {
      first = false;
      throw StateError('Respuesta interrumpida después de guardar.');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['POS_S5_VISUAL_DIR'] != null) {
      final font = FontLoader('Roboto')
        ..addFont(
          File(
            '/System/Library/Fonts/Supplemental/Arial.ttf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await icons.load();
    }
  });
  for (final width in [320.0, 1024.0]) {
    for (final mode in AppMode.values) {
      testWidgets(
        'S5 público conforme $width ${mode.name}: revisión, doble toque, historial y reapertura SQLite',
        (t) async {
          final dir = Directory.systemTemp.createTempSync('s5-ui-');
          final file = File('${dir.path}/db.sqlite');
          var h = ProductSupplierHarness(
            mode: mode,
            database: AppDatabase.forTesting(NativeDatabase(file)),
          );
          final id = (await t.runAsync(() => confirmedOrder(h)))!;
          final original = (await h.tracking.orders.find(
            id,
          ))!.document.toJson();
          register(h);
          t.view.physicalSize = Size(width, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(() async {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();

            await getIt.reset();

            await t.runAsync(h.dispose);

            dir.deleteSync(recursive: true);
            t.view.resetPhysicalSize();
            t.view.resetDevicePixelRatio();
          });
          await t.pumpWidget(
            MaterialApp(
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: RepaintBoundary(
                  key: const ValueKey('capture'),
                  child: w!,
                ),
              ),
              home: const SupplierOrdersScreen(),
            ),
          );
          await t.pumpAndSettle();
          await tap(t, 'Pendientes de recibir');
          await t.ensureVisible(find.byKey(ValueKey(id)));
          await t.tap(find.byKey(ValueKey(id)));
          await t.pumpAndSettle();
          expect(find.byType(SupplierOrderDetailScreen), findsOneWidget);
          await tap(t, 'Llegó conforme');
          expect(find.text('Revisar recepción'), findsOneWidget);
          expect(
            find.textContaining(
              'Saldo vigente 3 + entrada 4 = saldo previsto 7 pza',
            ),
            findsOneWidget,
          );
          expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
          await capture(t, 'conforme-${width.toInt()}-${mode.name}');

          final confirm = find.text('Confirmar entrada de inventario');
          if (confirm.evaluate().isEmpty) {
            await t.scrollUntilVisible(
              confirm,
              250,
              scrollable: find
                  .byWidgetPredicate(
                    (w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.down,
                  )
                  .last,
            );
          }
          await t.ensureVisible(confirm);
          await t.pumpAndSettle();

          await t.tap(confirm);
          await t.tap(confirm, warnIfMissed: false);
          await t.pumpAndSettle();
          expect((await h.db.select(h.db.supplierReceipts).get()).length, 1);
          expect(
            (await h.db.select(h.db.inventoryBalances).get())
                .single
                .quantityOnHandAtomic,
            7,
          );
          expect(
            (await h.tracking.orders.find(id))!.document.toJson(),
            original,
          );

          await tap(t, 'Volver al detalle');
          expect(
            find.textContaining(
              mode == AppMode.standalone
                  ? 'sin sincronización requerida'
                  : 'sincronización pendiente',
            ),
            findsWidgets,
          );
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();

          await getIt.reset();

          await t.runAsync(h.dispose);

          h = ProductSupplierHarness(
            mode: mode,
            database: AppDatabase.forTesting(NativeDatabase(file)),
          );
          register(h);
          await t.runAsync(() => h.db.customSelect('SELECT 1').get());
          await t.pumpWidget(
            MaterialApp(home: SupplierOrderDetailScreen(orderId: id)),
          );
          await t.pumpAndSettle();
          expect(
            find.textContaining('Importe acumulado recibido: 140.04'),
            findsOneWidget,
          );
          expect(find.text('Recibir mercancía'), findsNothing);
          expect(
            (await h.db.select(h.db.eventRefs).get()).isEmpty,
            mode == AppMode.standalone,
          );
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        },
      );
    }
  }
  testWidgets(
    'S5 excepciones: errores, cero, exceso, precio, volver, parcial y cierre',
    (t) async {
      final h = ProductSupplierHarness();
      final id = (await t.runAsync(() => confirmedOrder(h)))!;
      register(h);
      addTearDown(() async {
        await getIt.reset();
        await t.runAsync(h.dispose);
      });
      await t.pumpWidget(
        MaterialApp(home: SupplierOrderDetailScreen(orderId: id)),
      );
      await t.pumpAndSettle();
      await tap(t, 'Recibir mercancía');
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), '-1');
      await tap(t, 'Revisar recepción');
      expect(find.textContaining('sin signo'), findsOneWidget);
      expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
      await t.enterText(fields.at(0), '0');
      await tap(t, 'Revisar recepción');
      expect(find.textContaining('Cero no genera'), findsOneWidget);
      await t.enterText(fields.at(0), '5');
      await t.enterText(fields.at(1), '12.50');
      await tap(t, 'Revisar recepción');
      await tap(t, 'Confirmar entrada de inventario');
      expect(find.textContaining('cada exceso'), findsOneWidget);
      expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
      await tap(t, 'Volver a editar');
      expect(t.widget<TextField>(fields.at(0)).controller!.text, '5');
      await t.enterText(fields.at(0), '3');
      await tap(t, 'Revisar recepción');
      await tap(t, 'Confirmar entrada de inventario');
      await tap(t, 'Volver al detalle');
      final repo = DriftSupplierOrderRepository(h.db);
      final partial = (await repo.readDetail(id))!;
      expect(partial.pending(partial.order.document.items.single), 1);
      expect(partial.receivedTotal, 3750);
      await tap(t, 'Cerrar faltantes');
      expect(find.textContaining('Café: 1 pza'), findsOneWidget);
      await tap(t, 'Volver');
      expect((await h.tracking.orders.find(id))!.status, 'partial');
      await tap(t, 'Cerrar faltantes');
      await tap(t, 'Confirmar cierre');
      expect((await h.tracking.orders.find(id))!.status, 'closed');
      expect(
        (await h.db.select(h.db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        6,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'S5 cambio de base conserva captura; cancelar no recibe y salida informa descarte',
    (t) async {
      final h = ProductSupplierHarness();
      final id = (await t.runAsync(() => confirmedOrder(h)))!;
      register(h);
      addTearDown(() async {
        await getIt.reset();
        await t.runAsync(h.dispose);
      });
      await t.pumpWidget(
        MaterialApp(home: SupplierOrderDetailScreen(orderId: id)),
      );
      await t.pumpAndSettle();
      await tap(t, 'Recibir mercancía');
      await t.enterText(find.byType(TextField).at(0), '2');
      await tap(t, 'Revisar recepción');
      await t.runAsync(() async {
        await h.orders.receive(await receipt(h, id, 1));
      });
      await t.pumpAndSettle();
      await tap(t, 'Confirmar entrada de inventario');
      expect(find.textContaining('vuelve a revisar'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '2',
      );
      await tap(t, 'Revisar recepción');
      expect(find.textContaining('Recibido anteriormente: 1'), findsOneWidget);
      await tap(t, 'Cancelar edición');
      expect(
        find.textContaining('no es una recepción guardada'),
        findsOneWidget,
      );
      await tap(t, 'Seguir editando');
      await tap(t, 'Volver a editar');
      expect(
        t.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '2',
      );
      await tap(t, 'Cancelar edición');
      await tap(t, 'Descartar y salir');
      expect((await h.db.select(h.db.supplierReceipts).get()).length, 1);
      expect(
        (await h.db.select(h.db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        4,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'S5 exceso aceptado precio cero, respuesta interrumpida, reintento original y conflicto visible',
    (t) async {
      final h = ProductSupplierHarness(mode: AppMode.serverSync);
      final id = (await t.runAsync(() => confirmedOrder(h)))!;
      register(h);
      await getIt.unregister<SupplierOrderCommandService>();
      getIt.registerSingleton<SupplierOrderCommandService>(_LostResponse(h));
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        await getIt.reset();
        await t.runAsync(h.dispose);
      });
      await t.pumpWidget(
        MaterialApp(home: SupplierOrderDetailScreen(orderId: id)),
      );
      await t.pumpAndSettle();
      await tap(t, 'Recibir mercancía');
      await t.enterText(find.byType(TextField).at(0), '5');
      await t.enterText(find.byType(TextField).at(1), '0');
      await tap(t, 'Revisar recepción');
      await tap(t, 'Acepto el exceso de 1 pza');
      await tap(t, 'Confirmar entrada de inventario');
      expect(find.textContaining('Respuesta interrumpida'), findsOneWidget);
      final saved = (await h.db.select(h.db.supplierReceipts).get()).single;
      await tap(t, 'Reintentar el mismo intento');
      expect(
        (await h.db.select(h.db.supplierReceipts).get()).single.id,
        saved.id,
      );
      await tap(t, 'Volver al detalle');
      // Simulated transport rejection, real S4 inverse + event status transaction.
      await t.runAsync(() async {
        final e = (await h.tracking.orders.eventById(saved.eventId))!;
        await h.db.transaction(() async {
          await h.tracking.orders.restore(e);
          await h.db.eventDao.actualizarEstadoSincronizacion(
            e.eventId,
            'conflict',
            rejectionReason: 'Otra terminal recibió primero',
          );
        });
      });
      await t.pumpAndSettle();
      expect(
        find.textContaining('Otra terminal recibió primero'),
        findsOneWidget,
      );
      expect((await h.db.select(h.db.supplierReceipts).get()), isEmpty);
      expect(
        (await h.db.select(h.db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        3,
      );
      await tap(t, 'Revisar intención rechazada ${saved.id}');
      expect(
        t.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '5',
      );
      expect(
        t.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '0.00',
      );
      expect(find.textContaining('No se reenvía'), findsOneWidget);
      await tap(t, 'Revisar recepción');
      expect(find.text('Acepto el exceso de 1 pza'), findsOneWidget);
      expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'S5 remanente recibe otra vez y cancelación conserva historial sin inventario',
    (t) async {
      final h = ProductSupplierHarness();
      final id = (await t.runAsync(() => confirmedOrder(h)))!;
      register(h);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        await getIt.reset();
        await t.runAsync(h.dispose);
      });
      await t.pumpWidget(
        MaterialApp(home: SupplierOrderDetailScreen(orderId: id)),
      );
      await t.pumpAndSettle();
      await tap(t, 'Recibir mercancía');
      await t.enterText(find.byType(TextField).at(0), '3');
      await tap(t, 'Revisar recepción');
      await tap(t, 'Confirmar entrada de inventario');
      await tap(t, 'Volver al detalle');
      expect(find.text('Cancelar pedido'), findsNothing);
      await tap(t, 'Llegó conforme');
      expect(find.textContaining('Esta recepción: 1 pza'), findsOneWidget);
      await tap(t, 'Confirmar entrada de inventario');
      await tap(t, 'Volver al detalle');
      expect((await h.db.select(h.db.supplierReceipts).get()).length, 2);
      expect(
        (await h.db.select(h.db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        7,
      );
      final doc = await h.newOrder(quantity: 2);
      await h.orders.save(await h.orderCommand(doc));
      await h.orders.save(
        await h.orderCommand(await h.based(doc.orderId), confirm: true),
      );
      await t.pumpWidget(
        MaterialApp(
          home: SupplierOrderDetailScreen(
            key: ValueKey(doc.orderId),
            orderId: doc.orderId,
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Cancelar pedido');
      await tap(t, 'Confirmar cancelación');
      expect((await h.tracking.orders.find(doc.orderId))!.status, 'cancelled');
      expect(
        (await h.db.select(h.db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        7,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  for (final width in [320.0, 1024.0]) {
    testWidgets(
      'S5 dimensiones separadas $width: kg/piezas, nombres largos, teclado y foco',
      (t) async {
        final h = ProductSupplierHarness();
        final id = (await t.runAsync(() => confirmedOrder(h)))!;
        final existing = (await h.tracking.orders.find(id))!.document;
        await t.runAsync(
          () => h.commands.crearArticulo(
            CrearArticuloCommand.conVariantes(
              nombre:
                  'Arroz integral de grano largo de producción regional con nombre extenso para comprobar lectura',
              saleConfiguration: MeasuredSaleConfiguration(
                saleUnitId: InventoryUnitIds.kilogram,
                priceReferenceQuantityAtomic: 1000,
              ),
              variantes: [
                CrearArticuloVarianteCommand.conProveedores(
                  nombre: 'Presentación a granel de temporada',
                  precioVenta: '50',
                  costoEstandar: null,
                  inventoryUnitId: InventoryUnitIds.kilogram,
                  initialStockQuantity: '2',
                  proveedores: [
                    ProveedorVariante(
                      proveedorId: existing.supplierId,
                      precioInformadoMenor: 2500,
                      fechaInformadaMs: 100,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        final candidates = (await h.tracking.orders.candidates())
            .where((c) => c.supplierId == existing.supplierId)
            .toList();
        final doc = orderDocument(
          id: const Uuid().v4(),
          base: null,
          supplierId: existing.supplierId,
          name: existing.supplierNameSnapshot,
          phone: null,
          currency: 'MXN',
          occurredAtMs: 700,
          items: [
            for (final c in candidates)
              candidateLine(
                c,
                const Uuid().v4(),
                c.dimension == 'count' ? 2 : 1500,
              ),
          ],
        );
        await h.orders.save(await h.orderCommand(doc));
        await h.orders.save(
          await h.orderCommand(await h.based(doc.orderId), confirm: true),
        );
        register(h);
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();

          await getIt.reset();

          await t.runAsync(h.dispose);

          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        await t.pumpWidget(
          MaterialApp(
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: RepaintBoundary(key: const ValueKey('capture'), child: w!),
            ),
            home: SupplierOrderDetailScreen(orderId: doc.orderId),
          ),
        );
        await t.pumpAndSettle();
        await tap(t, 'Recibir mercancía');
        final field = find.byType(TextField).first;
        await t.showKeyboard(field);
        await t.enterText(field, '1.25');
        await t.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, isNotNull);
        await capture(t, 'captura-mixta-${width.toInt()}');
        await tap(t, 'Revisar recepción');
        expect(find.textContaining('Esta recepción: 1.25 kg'), findsOneWidget);
        expect(find.textContaining('Esta recepción: 2 pza'), findsOneWidget);
        expect(find.textContaining('Total de unidades'), findsNothing);
        await capture(t, 'revision-mixta-${width.toInt()}');
        expect(t.takeException(), isNull);
        await tap(t, 'Volver a editar');
        expect(
          t.widget<TextField>(find.byType(TextField).first).controller!.text,
          '1.25',
        );
        final countQuantity = find.byKey(
          ValueKey(
            'quantity-${doc.items.singleWhere((l) => l.dimension == "count").id}',
          ),
        );
        if (countQuantity.evaluate().isEmpty) {
          await t.scrollUntilVisible(
            countQuantity,
            250,
            scrollable: find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .last,
          );
        }
        await t.ensureVisible(countQuantity);
        await t.enterText(countQuantity, '0');
        await tap(t, 'Revisar recepción');
        await tap(t, 'Confirmar entrada de inventario');
        await tap(t, 'Volver al detalle');
        final saved = (await t.runAsync(
          () => DriftSupplierOrderRepository(h.db).readDetail(doc.orderId),
        ))!;
        expect(saved.receipts.single.items.length, 1);
        expect(saved.receipts.single.items.single.quantityAtomic, 1250);
        final ticket = SupplierDocumentTicket.build(
          saved,
          receipt: saved.receipts.single,
        );
        expect(ticket.itemRows.single[2], '1.25 kg');
        expect(ticket.itemRows.single[1], '25.00 / 1 kg');
        final output = Platform.environment['POS_S5_VISUAL_DIR'];
        if (output != null) {
          await t.runAsync(() async {
            await File(
              '$output/ticket-medido-${width.toInt()}.png',
            ).writeAsBytes(await TicketImageGenerator().generate(ticket));
          });
        }
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'S5 precio desconocido permanece vacío; corregir precio conserva cantidad',
    (t) async {
      final h = ProductSupplierHarness();
      final existing = (await t.runAsync(() => confirmedOrder(h)))!;
      final source = (await h.tracking.orders.find(existing))!.document;
      final newDoc = await h.newOrder(
        supplierId: source.supplierId,
        quantity: 2,
      );
      final doc = SupplierOrderDraftSavedPayload.fromJson({
        ...newDoc.toJson(),
        'total_minor': null,
        'items': [
          for (final l in newDoc.items)
            {...l.toJson(), 'quoted_price_minor': null, 'total_minor': null},
        ],
      });
      await h.orders.save(await h.orderCommand(doc));
      await h.orders.save(
        await h.orderCommand(await h.based(doc.orderId), confirm: true),
      );
      register(h);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        await getIt.reset();
        await t.runAsync(h.dispose);
      });
      await t.pumpWidget(
        MaterialApp(home: SupplierOrderDetailScreen(orderId: doc.orderId)),
      );
      await t.pumpAndSettle();
      await tap(t, 'Recibir mercancía');
      expect(
        t.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '',
      );
      await tap(t, 'Revisar recepción');
      expect(find.textContaining('Ingresa el precio real'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '2',
      );
      await t.enterText(find.byType(TextField).at(1), '10');
      await tap(t, 'Revisar recepción');
      await tap(t, 'Confirmar entrada de inventario');
      await tap(t, 'Volver al detalle');
      expect(
        (await h.tracking.orders.find(doc.orderId))!.document.totalMinor,
        isNull,
      );
      expect(
        (await h.db.select(h.db.supplierReceipts).get()).single.totalMinor,
        2000,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
