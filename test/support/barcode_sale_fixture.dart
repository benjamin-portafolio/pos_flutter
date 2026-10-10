import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
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
import 'package:pos_flutter/domain/articulos/variante_por_codigo_barras.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/ventas/sale_draft.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/sale_barcode_read_coordinator.dart';

/// Los hooks solo detienen consultas/comandos; la persistencia y el flujo de
/// eventos son reales, sobre una base aislada que nunca abre la instalación.
class BarcodeSaleFixture {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final config = AppConfigController(AppConfig.initial);
  final lookups = <String>[];
  final attempts = <AgregarProductoBorradorCommand>[];
  Future<void> Function(String)? beforeLookup;
  Future<void> Function(AgregarProductoBorradorCommand)? beforeSave;
  Future<void> Function(AgregarProductoBorradorCommand)? afterSave;

  late final products = _Products(this);
  late final commands = _Commands(this);
  late final drafts = SaleDraftRepositoryImpl(
    saleDao: db.saleDao,
    userId: 'user',
    deviceId: 'device',
  );
  late final processor = EventProcessor(
    handlers: {
      ProductoAgregadoBorradorPayload.eventType: VentaBorradorEventHandler(
        db.saleDao,
      ).apply,
    },
  );
  late final events = DriftLocalEventStore(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    appConfigController: config,
    eventProcessor: processor,
  );
  late final coordinator = SaleBarcodeReadCoordinator(
    products: products,
    commands: commands,
  );

  Future<void> seed() async {
    for (final data in [
      ('A', '001'),
      ('B', '002'),
      ('C', '003'),
      ('D', '003'),
      ('M', '004'),
    ]) {
      final measured = data.$1 == 'M';
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: 'product-${data.$1}',
              name: data.$1,
              saleMode: Value(measured ? 'measured' : 'unit'),
              saleUnitId: Value(measured ? InventoryUnitIds.kilogram : null),
              priceReferenceQuantityAtomic: Value(measured ? 1000 : null),
            ),
          );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: data.$1,
              productId: 'product-${data.$1}',
              barcode: Value(data.$2),
              salePriceMinor: measured ? 20000 : 100,
              sortOrder: 0,
            ),
          );
    }
  }

  Future<SaleDraft?> get draft => drafts.watchCurrentDraft().first;

  Future<List<ProductoAgregadoBorradorPayload>> payloads() async => [
    for (final event in await db.select(db.events).get())
      ProductoAgregadoBorradorPayload.fromJson(
        (jsonDecode(event.payload) as Map).cast<String, Object?>(),
      ),
  ];

  Future<void> expectNoWrites() async {
    expect(await db.select(db.events).get(), isEmpty);
    expect(await db.select(db.eventRefs).get(), isEmpty);
    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.saleItems).get(), isEmpty);
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Estado de lector no alcanzado');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> dispose() async {
    await db.close();
    await config.dispose();
  }
}

class _Products extends ProductoRepositoryImpl {
  _Products(this.fixture) : super(productoDao: fixture.db.productoDao);
  final BarcodeSaleFixture fixture;

  @override
  Future<List<VariantePorCodigoBarras>> buscarVariantesPorCodigoBarras(
    String code,
  ) async {
    fixture.lookups.add(code);
    await fixture.beforeLookup?.call(code);
    return super.buscarVariantesPorCodigoBarras(code);
  }
}

class _Commands extends VentaBorradorCommandService {
  _Commands(this.fixture)
    : super(
        store: fixture.db.saleDao,
        products: DriftProductoProjectionStore(
          productoDao: fixture.db.productoDao,
        ),
        units: UnidadInventarioRepositoryImpl(unitDao: fixture.db.unitDao),
        context: const LocalCommandContext(userId: 'user', deviceId: 'device'),
        events: fixture.events,
      );
  final BarcodeSaleFixture fixture;

  @override
  Future<void> agregar(AgregarProductoBorradorCommand command) async {
    fixture.attempts.add(command);
    await fixture.beforeSave?.call(command);
    await super.agregar(command);
    await fixture.afterSave?.call(command);
  }
}
