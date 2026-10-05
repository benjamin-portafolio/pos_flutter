import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_read_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  late AppConfigController config;
  late VentaBorradorCommandService commands;
  late ProductoRepositoryImpl products;
  late SaleDraftRepositoryImpl drafts;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('barcode-local-flow-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    db = AppDatabase();
    config = AppConfigController(AppConfig.initial);
    products = ProductoRepositoryImpl(productoDao: db.productoDao);
    drafts = SaleDraftRepositoryImpl(
      saleDao: db.saleDao,
      userId: 'user',
      deviceId: 'device',
    );
    commands = VentaBorradorCommandService(
      store: db.saleDao,
      products: DriftProductoProjectionStore(productoDao: db.productoDao),
      units: UnidadInventarioRepositoryImpl(unitDao: db.unitDao),
      context: const LocalCommandContext(userId: 'user', deviceId: 'device'),
      events: DriftLocalEventStore(
        db: db,
        eventDao: db.eventDao,
        eventRefDao: db.eventRefDao,
        appConfigController: config,
        eventProcessor: EventProcessor(
          handlers: {
            ProductoAgregadoBorradorPayload.eventType:
                VentaBorradorEventHandler(db.saleDao).apply,
          },
        ),
      ),
    );
    for (final entry in {
      'A': '001',
      'B': '002',
      'C': '003',
      'D': '003',
    }.entries) {
      await db
          .into(db.products)
          .insert(ProductsCompanion.insert(id: entry.key, name: entry.key));
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: entry.key,
              productId: entry.key,
              barcode: Value(entry.value),
              salePriceMinor: 100,
              sortOrder: 0,
            ),
          );
    }
  });
  tearDown(() async {
    await db.close();
    await config.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  for (final mode in AppMode.values) {
    test(
      'compuerta → consulta → comando → evento → borrador en ${mode.name}',
      () async {
        config.update(AppConfig.initial.copyWith(mode: mode));
        var now = Duration.zero;
        final gate = BarcodeReadGate(clock: () => now)..setCameraActive(true);
        Future<String> read(String code) async {
          final candidates = await products.buscarVariantesPorCodigoBarras(
            code,
          );
          if (candidates.isEmpty) return 'Desconocido';
          if (candidates.length != 1) return 'Ambiguo';
          await commands.agregar(
            AgregarProductoBorradorCommand(
              variantId: candidates.single.varianteId,
            ),
          );
          return 'Guardado';
        }

        Future<void> observe(String code) async {
          final accepted = gate.observe({code});
          if (accepted != null) await read(accepted);
        }

        await observe('999');
        await observe('999');
        await observe('003');
        await observe('003');
        expect(await db.select(db.events).get(), isEmpty);
        expect(await db.select(db.sales).get(), isEmpty);

        await observe('001');
        for (var i = 0; i < 5; i++) {
          now += const Duration(milliseconds: 200);
          await observe('001');
        }
        await observe('002');
        await observe('001');
        final sequence = (await drafts.watchCurrentDraft().first)!;
        expect(sequence.items.map((item) => item.quantity), [2, 1]);
        expect(sequence.totalMinor, 300);
        now += const Duration(milliseconds: 1100);
        await observe('001');
        final sale = (await drafts.watchCurrentDraft().first)!;
        expect(sale.items.map((item) => item.variantId), ['A', 'B']);
        expect(sale.items.map((item) => item.quantity), [3, 1]);
        expect(sale.totalMinor, 400);
        expect(await db.select(db.sales).get(), hasLength(1));
        final events = await db.select(db.events).get();
        expect(events, hasLength(4));
        expect(
          events.every((event) => event.deliveryStatus == 'not_required'),
          isTrue,
        );
        expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
        final refs = await db.select(db.eventRefs).get();
        expect(refs.length, mode == AppMode.standalone ? 0 : 16);
        if (mode == AppMode.serverSync) {
          for (final event in events) {
            final payload = ProductoAgregadoBorradorPayload.fromJson(
              (jsonDecode(event.payload) as Map).cast<String, Object?>(),
            );
            final eventRefs = refs.where((ref) => ref.eventId == event.eventId);
            expect(
              eventRefs.map(
                (ref) => (ref.refType, ref.refId, ref.relationship),
              ),
              unorderedEquals([
                ('sale', sale.id, 'affects'),
                ('sale_item', payload.saleItemId, 'affects'),
                ('product', payload.item.variantId, 'uses'),
                ('product_variant', payload.item.variantId, 'uses'),
              ]),
            );
            expect(
              eventRefs.every(
                (ref) =>
                    ref.source == 'local_pending' && ref.serverSequence == null,
              ),
              isTrue,
            );
          }
        }
        expect(await db.select(db.inventoryMovements).get(), isEmpty);
        // Reconexión de producción: incluye la comprobación de esquema al
        // arrancar y el executor en otro isolate, sin fakes de persistencia.
        await db.close();
        db = AppDatabase();
        final restarted = (await SaleDraftRepositoryImpl(
          saleDao: db.saleDao,
          userId: 'user',
          deviceId: 'device',
        ).watchCurrentDraft().first)!;
        expect(restarted.id, sale.id);
        expect(
          restarted.items.map((item) => item.id),
          sale.items.map((item) => item.id),
        );
        expect(restarted.items.map((item) => item.quantity), [3, 1]);
        expect(restarted.totalMinor, 400);
        expect(await db.select(db.events).get(), hasLength(4));
        expect(
          await db.select(db.eventRefs).get(),
          hasLength(mode == AppMode.standalone ? 0 : 16),
        );
        expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
      },
    );
  }
}
