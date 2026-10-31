import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/cambiar_tarifa_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:http/testing.dart';
import 'package:pos_flutter/application/sync/exceptions/sync_push_exception.dart';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/sync_conflict_report_service.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

import '../support/product_supplier_harness.dart';

// Extiende los arneses product/supplier/tracking existentes. No simula servidor,
// aceptación ni conflictos. SQL se limita al schema descartable del arnés HTTP.
void main() {
  final url = Platform.environment['POS_OFFER_SYNC_URL'];
  final skip = url == null
      ? 'Requires POS_OFFER_SYNC_URL and POS_OFFER_PG_SCHEMA (isolated Nest/PostgreSQL).'
      : false;
  late Directory directory;
  late String run;
  final opened = <ProductSupplierHarness>[];
  final oldWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    if (url != null) {
      expect(Uri.parse(url).host, '127.0.0.1');
      expect(Platform.environment['DATABASE_HOST'], '127.0.0.1');
      expect(
        Platform.environment['DATABASE_NAME'],
        startsWith('pos_nest_test_'),
      );
      expect(
        Platform.environment['POS_OFFER_PG_SCHEMA'],
        matches(r'^seg_phase3_http_[0-9]+_[0-9]+$'),
      );
    }
  });
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = oldWarning,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_offer_http_');
    run = const Uuid().v4();
  });
  tearDown(() async {
    for (final h in opened.toList()) {
      await h.dispose();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });
  ProductSupplierHarness terminal(String letter) {
    final h = ProductSupplierHarness(
      database: AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/$letter.sqlite')),
      ),
      mode: AppMode.serverSync,
      context: LocalCommandContext(
        deviceId: '$run-$letter',
        userId: 'offer-session3',
      ),
    );
    opened.add(h);
    return h;
  }

  Future<void> close(ProductSupplierHarness h) async {
    opened.remove(h);
    await h.dispose();
  }

  Future<ProductoCreadoPayload> state(ProductSupplierHarness h, String id) =>
      h.tracking.products.snapshot(id);
  Future<String> create(
    ProductSupplierHarness h, {
    bool measured = false,
    bool track = true,
    String? minimum = '5',
  }) async {
    await h.commands.crearArticulo(
      CrearArticuloCommand.conVariantes(
        nombre: 'Ofertas $run',
        saleConfiguration: measured
            ? MeasuredSaleConfiguration(
                saleUnitId: InventoryUnitIds.gram,
                priceReferenceQuantityAtomic: 1,
              )
            : const UnitSaleConfiguration(),
        variantes: [
          for (var i = 0; i < 2; i++)
            CrearArticuloVarianteCommand(
              nombre: i == 0 ? 'Primera' : 'Segunda',
              precioVenta: '10',
              costoEstandar: null,
              inventoryUnitId: !track
                  ? null
                  : measured
                  ? InventoryUnitIds.kilogram
                  : InventoryUnitIds.piece,
              initialStockQuantity: !track
                  ? null
                  : measured
                  ? '1.5'
                  : '6',
              offerPrice: i == 0 && minimum != null
                  ? CambioExplicito.establecer(minimum)
                  : const CambioExplicito.conservar(),
            ),
        ],
      ),
    );
    return h.appends.last.event.aggregateId;
  }

  Future<void> save(
    ProductSupplierHarness h,
    String id, {
    CambioExplicito<String?> minimum = const CambioExplicito.conservar(),
    String? name,
    String? secondBarcode,
  }) async {
    final snapshot = await state(h, id);
    final p = (await h.tracking.products.findProductById(id))!;
    await h.commands.actualizarArticulo(
      productId: id,
      baseEventId: p.lastEventId!,
      variantIds: snapshot.variantes.map((v) => v.id).toList(),
      command: CrearArticuloCommand.conVariantes(
        nombre: name ?? snapshot.nombre,
        saleConfiguration: snapshot.saleConfiguration,
        variantes: [
          for (var i = 0; i < snapshot.variantes.length; i++)
            CrearArticuloVarianteCommand(
              nombre: snapshot.variantes[i].nombre,
              precioVenta: '10',
              costoEstandar: null,
              codigoBarras: i == 1
                  ? secondBarcode ?? snapshot.variantes[i].codigoBarras
                  : snapshot.variantes[i].codigoBarras,
              inventoryUnitId: p.saleConfiguration is MeasuredSaleConfiguration
                  ? InventoryUnitIds.kilogram
                  : InventoryUnitIds.piece,
              offerPrice: i == 0 ? minimum : const CambioExplicito.conservar(),
            ),
        ],
      ),
    );
  }

  Future<void> sync(ProductSupplierHarness h) async {
    for (
      var i = 0;
      i < 30 && (await h.tracking.history.pendingEvents()).isNotEmpty;
      i++
    ) {
      final pre = await h.tracking.preflight(url!).preflightPendingEvents();
      if (pre.requiresFullPullBeforePush) {
        await h.tracking.pull(url).pullAvailableEvents();
      }
      final report = await h.tracking.push(url).pushPendingEvents();
      expect(
        report.rejected,
        0,
        reason: (await h.tracking.storedEvents())
            .where((e) => e.deliveryStatus == 'rejected')
            .map((e) => e.rejectionReason)
            .join(';'),
      );
      expect(report.conflicts, 0);
      await h.tracking.pull(url).pullAvailableEvents(limit: 3);
    }
    expect(await h.tracking.history.pendingEvents(), isEmpty);
  }

  Future<Map<String, dynamic>> send(SyncEvent e) async {
    final response = await http.post(
      Uri.parse('$url/sync/push'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'device_id': e.deviceId,
        'last_full_pull_server_sequence': 0,
        'events': [e.toPushJson()],
      }),
    );
    expect(response.statusCode, 201, reason: response.body);
    return Map<String, dynamic>.from(
      (jsonDecode(response.body)['results'] as List).single as Map,
    );
  }

  Future<void> rewrite(
    ProductSupplierHarness h,
    SyncEvent e,
    Map<String, Object?> payload,
  ) => (h.db.update(h.db.events)..where((r) => r.eventId.equals(e.eventId)))
      .write(EventsCompanion(payload: Value(jsonEncode(payload))));
  Future<void> converged(
    ProductSupplierHarness a,
    ProductSupplierHarness b,
    String id,
  ) async {
    await a.tracking.pull(url!).pullAvailableEvents(limit: 2);
    await b.tracking.pull(url).pullAvailableEvents(limit: 2);
    expect((await state(b, id)).toJson(), (await state(a, id)).toJson());
    final left = (await a.tracking.products.findProductById(id))!,
        right = (await b.tracking.products.findProductById(id))!;
    expect(right.version, left.version);
    expect(right.lastEventId, left.lastEventId);
    expect(right.lastServerSequence, left.lastServerSequence);
    for (final v in (await state(a, id)).variantes) {
      expect(
        (await b.tracking.inventory.findBalanceByItemId(
          v.inventoryItemId!,
        ))!.quantityOnHandAtomic,
        (await a.tracking.inventory.findBalanceByItemId(
          v.inventoryItemId!,
        ))!.quantityOnHandAtomic,
      );
    }
  }

  for (final method in ['cash', 'transfer']) {
    test(
      'S4 HTTP motor, cobro $method, precio histórico separado, duplicado y replay',
      () async {
        final a = terminal('S4-A-$method'), b = terminal('S4-B-$method');
        a.tracking.config.update(
          a.tracking.config.config.copyWith(cashEnabled: false),
        );
        final id = await create(a);
        await sync(a);
        final variant = (await state(a, id)).variantes.first.id;
        await a.tracking.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: variant),
        );
        var sale = (await a.db.saleDao.findDraft(
          a.tracking.context.userId,
          a.tracking.context.deviceId,
        ))!;
        await a.tracking.drafts.cambiarTarifa(
          CambiarTarifaVentaBorradorCommand(
            operationId: const Uuid().v4(),
            saleId: sale.id,
            pricingMode: 'offer',
            expectedVersion: sale.version,
            expectedDraftEventId: sale.lastEventId,
            expectedTotalMinor: sale.totalMinor,
          ),
        );
        await save(a, id, minimum: const CambioExplicito.establecer('7'));
        await sync(a);
        await a.tracking.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: variant),
        );
        sale = (await a.db.saleDao.findById(sale.id))!;
        expect(sale.totalMinor, 1200);
        final eventId = await a.tracking.sales.confirmar(
          ConfirmarVentaCommand(
            saleId: sale.id,
            expectedVersion: sale.version,
            expectedDraftEventId: sale.lastEventId!,
            expectedTotalMinor: 1200,
            paymentMethod: method,
          ),
        );
        final confirmation = (await a.tracking.storedEvents()).singleWhere(
          (e) => e.eventId == eventId,
        );
        final payload = VentaConfirmadaPayload.fromJson(confirmation.payload);
        expect(
          payload.lines.first.configurationEventId,
          isNot(payload.lines.first.snapshot.priceConfigurationEventId),
        );
        expect(payload.lines.map((l) => l.snapshot.unitPriceMinor), [500, 700]);
        await sync(a);
        expect((await send(confirmation))['status'], 'duplicate');
        await b.tracking.pull(url!).pullAvailableEvents(limit: 2);
        final remote = (await ConfirmedSaleRepositoryImpl(
          DriftConfirmedSaleStore(b.db),
        ).watchSales().first).singleWhere((s) => s.id == sale.id);
        expect(remote.totalMinor, 1200);
        expect(remote.pricingMode, 'offer');
        expect(remote.items.map((l) => l.effectivePriceOrigin), [
          'offer',
          'offer',
        ]);
        final c = terminal('S4-C-$method');
        await c.tracking.pull(url).pullAvailableEvents(limit: 2);
        final replay = (await ConfirmedSaleRepositoryImpl(
          DriftConfirmedSaleStore(c.db),
        ).watchSales().first).singleWhere((s) => s.id == sale.id);
        expect(replay.totalMinor, 1200);
        expect(replay.items.map((l) => l.unitPriceMinor), [500, 700]);
        expect(
          await b.db.saleDao.findDraft(
            a.tracking.context.userId,
            a.tracking.context.deviceId,
          ),
          isNull,
        );
      },
      skip: skip,
    );
  }

  test(
    'S6 HTTP venta offline con oferta llega después del retiro de variante',
    () async {
      final a = terminal('S6-online'), b = terminal('S6-offline');
      b.tracking.config.update(
        b.tracking.config.config.copyWith(cashEnabled: false),
      );
      final id = await create(a);
      await sync(a);
      await b.tracking.pull(url!).pullAvailableEvents();
      final before = await state(b, id);
      final variant = before.variantes.first.id;
      await b.tracking.drafts.agregar(
        AgregarProductoBorradorCommand(variantId: variant),
      );
      var sale = (await b.db.saleDao.findDraft(
        b.tracking.context.userId,
        b.tracking.context.deviceId,
      ))!;
      await b.tracking.drafts.cambiarTarifa(
        CambiarTarifaVentaBorradorCommand(
          operationId: const Uuid().v4(),
          saleId: sale.id,
          pricingMode: 'offer',
          expectedVersion: sale.version,
          expectedDraftEventId: sale.lastEventId,
          expectedTotalMinor: sale.totalMinor,
        ),
      );
      sale = (await b.db.saleDao.findById(sale.id))!;
      final eventId = await b.tracking.sales.confirmar(
        ConfirmarVentaCommand(
          saleId: sale.id,
          expectedVersion: sale.version,
          expectedDraftEventId: sale.lastEventId!,
          expectedTotalMinor: 500,
          paymentMethod: 'transfer',
        ),
      );
      // B ya cobró sin enviar; A retira la variante mediante el comando habitual.
      final current = await state(a, id);
      final product = (await a.tracking.products.findProductById(id))!;
      final kept = current.variantes.last;
      await a.commands.actualizarArticulo(
        productId: id,
        baseEventId: product.lastEventId!,
        variantIds: [kept.id],
        command: CrearArticuloCommand.conVariantes(
          nombre: current.nombre,
          saleConfiguration: current.saleConfiguration,
          variantes: [
            CrearArticuloVarianteCommand(
              nombre: kept.nombre,
              precioVenta: '10',
              costoEstandar: null,
              inventoryUnitId: InventoryUnitIds.piece,
            ),
          ],
        ),
      );
      await sync(a);
      await sync(b);
      final confirmation = (await b.tracking.storedEvents()).singleWhere(
        (e) => e.eventId == eventId,
      );
      expect((await send(confirmation))['status'], 'duplicate');
      final c = terminal('S6-new');
      await c.tracking.pull(url).pullAvailableEvents(limit: 2);
      final replay = (await ConfirmedSaleRepositoryImpl(
        DriftConfirmedSaleStore(c.db),
      ).watchSales().first).singleWhere((s) => s.id == sale.id);
      expect(replay.totalMinor, 500);
      expect(replay.items.single.variantId, variant);
      expect(replay.items.single.effectivePriceOrigin, 'offer');
      final retired = await c.tracking.products.findVariantById(variant);
      expect(retired!.active, isFalse);
      final resource = retired.inventoryItemId!;
      expect(
        (await c.tracking.inventory.findBalanceByItemId(
          resource,
        ))!.quantityOnHandAtomic,
        5,
      );
    },
    skip: skip,
  );

  test(
    'S3 HTTP dos terminales: alta, cambio, retirada, duplicado, reinicio y replay',
    () async {
      var a = terminal('A');
      final b = terminal('B');
      final id = await create(a);
      await sync(a);
      await converged(a, b, id);
      expect((await state(b, id)).variantes.first.offerPriceMinor, 500);
      final stocks = await a.db.select(a.db.inventoryBalances).get();
      final moves = await a.db.select(a.db.inventoryMovements).get();
      await save(a, id, minimum: const CambioExplicito.establecer('7'));
      final pending = (await a.tracking.history.pendingEvents()).single;
      await close(a);
      a = terminal('A');
      await sync(a);
      await converged(a, b, id);
      expect((await send(pending))['status'], 'duplicate');
      expect((await state(b, id)).variantes.first.offerPriceMinor, 700);
      await save(b, id, minimum: const CambioExplicito.establecer(null));
      await sync(b);
      await converged(a, b, id);
      expect((await state(a, id)).variantes.first.offerPriceMinor, isNull);
      expect((await state(a, id)).knowsOfferPrice, isTrue);
      expect(await a.db.select(a.db.inventoryBalances).get(), stocks);
      expect(await a.db.select(a.db.inventoryMovements).get(), moves);
      final c = terminal('C');
      await converged(a, c, id);
      expect((await state(c, id)).knowsOfferPrice, isTrue);
    },
    skip: skip,
  );
  test(
    'S3 HTTP concurrencia, preflight, cadena, reporte y resolución posterior',
    () async {
      final a = terminal('A');
      var b = terminal('B');
      final id = await create(a);
      await sync(a);
      await converged(a, b, id);
      await save(a, id, minimum: const CambioExplicito.establecer('7'));
      await save(b, id, secondBarcode: '00123');
      await save(b, id, minimum: const CambioExplicito.establecer('9'));
      final losing = await b.tracking.history.pendingEvents();
      await sync(a);
      final pre = await b.tracking.preflight(url!).preflightPendingEvents();
      expect(pre.impactingEvents, greaterThan(0));
      expect(await b.tracking.history.pendingEvents(), isEmpty);
      for (final e in losing) {
        expect(
          (await b.tracking.history.eventById(e.eventId))!.deliveryStatus,
          'conflict',
        );
      }
      await converged(a, b, id);
      final reported = await SyncConflictReportService(
        syncPersistence: b.tracking.history,
        endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
      ).reportLocalConflicts();
      expect(reported.conflicts, losing.length);
      // Resolver desde la base oficial actual requiere un nuevo comando.
      await save(
        b,
        id,
        minimum: const CambioExplicito.establecer('9'),
        secondBarcode: '00123',
      );
      await sync(b);
      await converged(a, b, id);
      await close(b);
      b = terminal('B');
      for (final e in losing.reversed) {
        await b.tracking.cleaner.hideConflictProjection(e);
      }
      await converged(a, b, id);
      expect((await state(b, id)).variantes.first.offerPriceMinor, 900);
      expect((await state(b, id)).variantes.last.codigoBarras, '00123');
    },
    skip: skip,
  );

  test(
    'S3 HTTP rechazo restaura oferta y cadena tras reapertura; undo tardío conserva sucesor',
    () async {
      var a = terminal('A');
      final b = terminal('B');
      final id = await create(a);
      await sync(a);
      await save(a, id, minimum: const CambioExplicito.establecer('7'));
      final root = (await a.tracking.history.pendingEvents()).single;
      final bad = jsonDecode(jsonEncode(root.payload)) as Map<String, dynamic>;
      (bad['before']['variants'] as List).first['offer_price_minor'] = 600;
      await save(a, id, minimum: const CambioExplicito.establecer('9'));
      final child = (await a.tracking.history.pendingEvents()).last;
      await rewrite(a, root, bad);
      await close(a);
      a = terminal('A');
      final result = await a.tracking.push(url!).pushPendingEvents();
      expect(result.rejected, 1);
      expect(result.conflicts, 1);
      expect(result.pending, 0);
      expect((await state(a, id)).variantes.first.offerPriceMinor, 500);
      expect((await state(a, id)).knowsOfferPrice, isTrue);
      await converged(a, b, id);
      await save(b, id, minimum: const CambioExplicito.establecer('9.5'));
      await sync(b);
      await converged(a, b, id);
      for (final e in [child, root]) {
        await a.tracking.cleaner.hideConflictProjection(e);
      }
      expect((await state(a, id)).variantes.first.offerPriceMinor, 950);
      await converged(a, b, id);
    },
    skip: skip,
  );

  test(
    'S3 HTTP borrado antiguo rechazado restaura oferta y presencia',
    () async {
      var a = terminal('A');
      final b = terminal('B');
      final id = await create(a);
      await sync(a);
      final p = (await a.tracking.products.findProductById(id))!;
      final before = await state(a, id);
      await a.commands.eliminarArticulo(
        productId: id,
        baseEventId: p.lastEventId!,
      );
      final deletion = (await a.tracking.history.pendingEvents()).single;
      final bad =
          jsonDecode(jsonEncode(deletion.payload)) as Map<String, dynamic>;
      for (final v in bad['before']['variants'] as List) {
        (v as Map).remove('offer_price_minor');
      }
      await rewrite(a, deletion, bad);
      await close(a);
      a = terminal('A');
      final result = await a.tracking.push(url!).pushPendingEvents();
      expect(result.rejected, 1);
      expect(
        (await a.tracking.history.eventById(deletion.eventId))!.rejectionReason,
        contains('Actualiza la app'),
      );
      expect((await state(a, id)).toJson(), before.toJson());
      await converged(a, b, id);
    },
    skip: skip,
  );
  test(
    'S3 HTTP receptor sin capacidad no recibe nuevos eventos ni pierde pendientes',
    () async {
      final a = terminal('A');
      final id = await create(a, track: false);
      final original = await a.tracking.history.pendingEvents();
      final real = http.Client();
      addTearDown(real.close);
      var posts = 0;
      final proxy = MockClient((request) async {
        if (request.url.path.endsWith('/sync/health')) {
          final response = await real.get(request.url);
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          body['capabilities'] = (body['capabilities'] as List)
              .where((c) => c != 'offer_pricing_v2')
              .toList();
          return http.Response(jsonEncode(body), response.statusCode);
        }
        posts++;
        return http.Response('Unexpected write', 500);
      });
      addTearDown(proxy.close);
      await expectLater(
        a.tracking.push(url!, client: proxy).pushPendingEvents(),
        throwsA(isA<SyncPushException>()),
      );
      expect(posts, 0);
      expect(
        (await a.tracking.history.pendingEvents()).map((e) => e.eventId),
        original.map((e) => e.eventId),
      );
      expect((await state(a, id)).variantes.first.offerPriceMinor, 500);
      await sync(a);
    },
    skip: skip,
  );
  test(
    'S3 HTTP respuesta perdida, reapertura y reintento duplicado conservan oferta',
    () async {
      var a = terminal('A');
      final b = terminal('B');
      final id = await create(a);
      await sync(a);
      await save(a, id, minimum: const CambioExplicito.establecer('8'));
      final event = (await a.tracking.history.pendingEvents()).single;
      final real = http.Client();
      addTearDown(real.close);
      var lost = false;
      final proxy = MockClient((request) async {
        final response = request.method == 'GET'
            ? await real.get(request.url, headers: request.headers)
            : await real.post(
                request.url,
                headers: request.headers,
                body: request.body,
              );
        if (request.url.path.endsWith('/sync/push') && !lost) {
          lost = true;
          throw const SocketException('respuesta perdida después del commit');
        }
        return response;
      });
      addTearDown(proxy.close);
      await expectLater(
        a.tracking.push(url!, client: proxy).pushPendingEvents(),
        throwsA(isA<SyncPushException>()),
      );
      expect(lost, isTrue);
      expect(
        (await a.tracking.history.eventById(event.eventId))!.deliveryStatus,
        'pending',
      );
      await close(a);
      a = terminal('A');
      final retry = await a.tracking.push(url).pushPendingEvents();
      expect(retry.synced, 1);
      expect(retry.rejected, 0);
      expect(retry.conflicts, 0);
      await converged(a, b, id);
      expect((await state(b, id)).variantes.first.offerPriceMinor, 800);
      expect((await send(event))['status'], 'duplicate');
    },
    skip: skip,
  );
}
