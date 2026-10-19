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
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/sync_conflict_report_service.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/minimum_stock_policy.dart';

import '../support/product_supplier_harness.dart';

// Extiende los arneses product/supplier/tracking existentes. No simula servidor,
// aceptación ni conflictos. SQL se limita al schema descartable del arnés HTTP.
void main() {
  final url = Platform.environment['POS_MINIMUM_SYNC_URL'];
  final skip = url == null
      ? 'Requires POS_MINIMUM_SYNC_URL and POS_MINIMUM_PG_SCHEMA (isolated Nest/PostgreSQL).'
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
        Platform.environment['POS_MINIMUM_PG_SCHEMA'],
        matches(r'^seg_phase3_http_[0-9]+_[0-9]+$'),
      );
    }
  });
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = oldWarning,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_minimum_http_');
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
        userId: 'minimum-session3',
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
    String? minimum = '5',
  }) async {
    await h.commands.crearArticulo(
      CrearArticuloCommand.conVariantes(
        nombre: 'Mínimos $run',
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
              inventoryUnitId: measured
                  ? InventoryUnitIds.kilogram
                  : InventoryUnitIds.piece,
              initialStockQuantity: measured ? '1.5' : '6',
              minimumStock: i == 0 && minimum != null
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
              minimumStock: i == 0
                  ? minimum
                  : const CambioExplicito.conservar(),
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
      final x = (await a.tracking.inventory.findBalanceByItemId(
        v.inventoryItemId!,
      ))!;
      final y = (await b.tracking.inventory.findBalanceByItemId(
        v.inventoryItemId!,
      ))!;
      expect(y.quantityOnHandAtomic, x.quantityOnHandAtomic);
      bool low(int stock) => const MinimumStockPolicy().isLow(
        minimumStockAtomic: v.minimumStockAtomic,
        quantityOnHandAtomic: stock,
        productActive: true,
        variantActive: true,
        hasDirectTracking: true,
        inventoryItemActive: true,
      );
      expect(low(y.quantityOnHandAtomic), low(x.quantityOnHandAtomic));
    }
  }

  Future<Object?> serverPhoto(String id) async {
    expect(Uuid.isValidUUID(fromString: id), isTrue);
    final env = Platform.environment,
        schema = Platform.environment['POS_MINIMUM_PG_SCHEMA']!;
    final variants =
        '(SELECT variant_id FROM "$schema".product_variants WHERE product_id = \'$id\')';
    final items =
        '(SELECT inventory_item_id FROM "$schema".product_variants WHERE product_id = \'$id\')';
    final sales =
        '(SELECT sale_id FROM "$schema".sale_items WHERE variant_id IN $variants)';
    final selections = {
      'resources':
          'SELECT * FROM "$schema".inventory_items WHERE inventory_item_id IN $items ORDER BY inventory_item_id',
      'balances':
          'SELECT * FROM "$schema".inventory_balances WHERE inventory_item_id IN $items ORDER BY inventory_item_id',
      'movements':
          'SELECT * FROM "$schema".inventory_movements WHERE inventory_item_id IN $items ORDER BY movement_id',
      'sales':
          'SELECT * FROM "$schema".sales WHERE sale_id IN $sales ORDER BY sale_id',
      'lines':
          'SELECT * FROM "$schema".sale_items WHERE sale_id IN $sales ORDER BY sale_item_id',
      'payments':
          'SELECT * FROM "$schema".sale_payments WHERE sale_id IN $sales ORDER BY payment_id',
    };
    final sql =
        'SELECT json_build_object(${selections.entries.map((e) => "'${e.key}', (SELECT coalesce(jsonb_agg(t), '[]'::jsonb) FROM (${e.value}) t)").join(',')})';
    final result = await Process.run('psql', [
      '-X',
      '-tA',
      '-v',
      'ON_ERROR_STOP=1',
      '-h',
      '127.0.0.1',
      '-p',
      env['DATABASE_PORT']!,
      '-U',
      env['DATABASE_USER']!,
      '-d',
      env['DATABASE_NAME']!,
      '-c',
      sql,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return jsonDecode(result.stdout.toString());
  }

  test(
    'A24/A27/A32/A33 HTTP: mínimo solo conserva inventario, ventas y clave; venta abierta confirma',
    () async {
      final a = terminal('A'), b = terminal('B');
      final id = await create(a);
      await sync(a);
      await converged(a, b, id);
      final v = (await state(a, id)).variantes.first;
      // Una venta ya aceptada da filas no vacías a la verificación de conservación.
      Future<void> add() => a.tracking.drafts.agregar(
        AgregarProductoBorradorCommand(variantId: v.id),
      );
      Future<void> confirm() async {
        final draft = (await a.db.select(a.db.sales).get()).last;
        await a.tracking.sales.confirmar(
          ConfirmarVentaCommand(
            saleId: draft.id,
            expectedDraftEventId: draft.lastEventId!,
            expectedTotalMinor: draft.totalMinor,
            paymentMethod: 'cash',
          ),
        );
      }

      await add();
      await confirm();
      await sync(a);
      await add();
      final key = await a.tracking.products.consumptionConfigurationKey(v.id);
      final photo = await serverPhoto(id);
      final stock = await a.db.select(a.db.inventoryBalances).get();
      final moves = await a.db.select(a.db.inventoryMovements).get();
      final sales = await a.db.select(a.db.sales).get();
      final resources = await a.db.select(a.db.inventoryItems).get();
      await save(a, id, minimum: const CambioExplicito.establecer('4'));
      expect(await a.tracking.products.consumptionConfigurationKey(v.id), key);
      expect(await a.db.select(a.db.inventoryBalances).get(), stock);
      expect(await a.db.select(a.db.inventoryMovements).get(), moves);
      expect(await a.db.select(a.db.sales).get(), sales);
      expect(await a.db.select(a.db.inventoryItems).get(), resources);
      final pending = (await a.tracking.history.pendingEvents())
          .where((e) => e.aggregateType == 'product')
          .single;
      expect(pending.deliveryStatus, 'pending');
      final refs = await a.db.select(a.db.eventRefs).get();
      expect(
        refs.where((r) => r.eventId == pending.eventId).map((r) => r.refType),
        isNot(contains('minimum_stock')),
      );
      await sync(a);
      await converged(a, b, id);
      expect(await serverPhoto(id), photo);
      await confirm();
      await sync(a);
      await converged(a, b, id);
      expect(
        (await a.tracking.inventory.findBalanceByItemId(
          v.inventoryItemId!,
        ))!.quantityOnHandAtomic,
        4,
      );
      expect((await state(b, id)).variantes.first.minimumStockAtomic, 4);
      final finalPhoto = await serverPhoto(id);
      expect((await send(pending))['status'], 'duplicate');
      expect(await serverPhoto(id), finalPhoto);
    },
    skip: skip,
  );

  test(
    'A11/A27/A30/A34 HTTP: pendientes en disco, cadena causal, ecos y replay desde cero',
    () async {
      var a = terminal('A');
      final b = terminal('B');
      final id = await create(a);
      await save(a, id, minimum: const CambioExplicito.establecer('7'));
      await save(a, id, minimum: const CambioExplicito.establecer('0'));
      final original = (await a.tracking.storedEvents())
          .where((e) => e.aggregateId == id)
          .toList();
      await expectLater(
        a.tracking.push('http://127.0.0.1:1').pushPendingEvents(),
        throwsException,
      );
      await close(a);
      a = terminal('A');
      final first = await a.tracking.push(url!).pushPendingEvents();
      expect(first.pending, greaterThanOrEqualTo(2));
      await a.tracking.pull(url).pullAvailableEvents();
      expect((await state(a, id)).variantes.first.minimumStockAtomic, 0);
      await sync(a);
      await converged(a, b, id);
      for (final e in original) {
        final duplicate = await send(e);
        expect(duplicate['status'], 'duplicate');
        expect(duplicate['original_sync_status'], 'synced');
      }
      final c = terminal('C');
      await converged(a, c, id);
      expect((await state(c, id)).variantes.first.minimumStockAtomic, 0);
      await save(a, id, minimum: const CambioExplicito.establecer(null));
      final successor = await state(a, id);
      final echoed = (await a.tracking.history.eventById(
        original.first.eventId,
      ))!;
      await a.tracking.remote.applySyncedEvents([echoed, echoed]);
      expect((await state(a, id)).toJson(), successor.toJson());
      await sync(a);
      await converged(a, b, id);
      await converged(a, c, id);
      expect((await state(c, id)).knowsMinimumStock, isTrue);
      expect((await state(c, id)).variantes.first.minimumStockAtomic, isNull);
    },
    skip: skip,
  );

  test(
    'A28/A29/A30 HTTP: mínimo contra otra variante, preflight, dependientes y resolución posterior',
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
      expect((await state(b, id)).variantes.first.minimumStockAtomic, 9);
      expect((await state(b, id)).variantes.last.codigoBarras, '00123');
    },
    skip: skip,
  );

  test(
    'A29/A30 HTTP: rechazo real restaura mínimo y pendientes tras reapertura; undo tardío respeta sucesor',
    () async {
      var a = terminal('A');
      final b = terminal('B');
      final id = await create(a);
      await sync(a);
      await save(a, id, minimum: const CambioExplicito.establecer('7'));
      final root = (await a.tracking.history.pendingEvents()).single;
      final bad = jsonDecode(jsonEncode(root.payload)) as Map<String, dynamic>;
      (bad['before']['variants'] as List).first['minimum_stock_atomic'] = 6;
      await save(a, id, minimum: const CambioExplicito.establecer('9'));
      final child = (await a.tracking.history.pendingEvents()).last;
      await rewrite(a, root, bad);
      await close(a);
      a = terminal('A');
      final result = await a.tracking.push(url!).pushPendingEvents();
      expect(result.rejected, 1);
      expect(result.conflicts, 1);
      expect(result.pending, 0);
      expect((await state(a, id)).variantes.first.minimumStockAtomic, 5);
      expect((await state(a, id)).knowsMinimumStock, isTrue);
      await converged(a, b, id);
      await save(b, id, minimum: const CambioExplicito.establecer('11'));
      await sync(b);
      await converged(a, b, id);
      for (final e in [child, root]) {
        await a.tracking.cleaner.hideConflictProjection(e);
      }
      expect((await state(a, id)).variantes.first.minimumStockAtomic, 11);
      await converged(a, b, id);
    },
    skip: skip,
  );

  test(
    'A15/A29 HTTP: borrado optimista legado rechazado restaura valores y presencia',
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
        (v as Map).remove('minimum_stock_atomic');
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
    'A10/A13/A14/A15/A34 HTTP: historia legada, promoción y rechazo antiguo incluso null conocido',
    () async {
      final a = terminal('A'), b = terminal('B');
      final id = await create(a, minimum: null);
      final creation = (await a.tracking.history.pendingEvents()).singleWhere(
        (e) => e.aggregateId == id,
      );
      final legacyJson =
          jsonDecode(jsonEncode(creation.payload)) as Map<String, dynamic>;
      for (final v in legacyJson['variants'] as List) {
        (v as Map).remove('minimum_stock_atomic');
      }
      await rewrite(a, creation, legacyJson);
      await sync(a);
      await converged(a, b, id);
      expect((await state(b, id)).knowsMinimumStock, isFalse);
      await save(b, id, name: 'Edición legada');
      await sync(b);
      await converged(a, b, id);
      expect((await state(a, id)).knowsMinimumStock, isFalse);
      await save(a, id, minimum: const CambioExplicito.establecer('5'));
      await sync(a);
      await converged(a, b, id);
      Future<void> rejectLegacy() async {
        final p = (await a.tracking.products.findProductById(id))!;
        final json = (await state(a, id)).toJson();
        for (final v in json['variants'] as List) {
          (v as Map).remove('minimum_stock_atomic');
        }
        for (final delete in [false, true]) {
          final e = SyncEvent(
            eventId: const Uuid().v4(),
            aggregateType: 'product',
            aggregateId: id,
            eventType: ProductoActualizadoPayload.eventType,
            deviceId: '$run-old-${const Uuid().v4()}',
            userId: 'legacy',
            localSequence: delete ? 2 : 1,
            createdAtLocal: DateTime.now(),
            baseVersion: p.version,
            baseServerSequence: p.lastServerSequence,
            payload: {
              'base_event_id': p.lastEventId,
              'before': json,
              'after': delete ? null : json,
              if (delete) 'delete_product': true,
            },
          );
          final result = await send(e);
          expect(result['status'], 'rejected');
          expect(result['reason'], contains('Actualiza la app'));
        }
      }

      await rejectLegacy();
      await save(a, id, minimum: const CambioExplicito.establecer(null));
      await sync(a);
      await rejectLegacy();
      await converged(a, b, id);
      final c = terminal('C');
      await converged(a, c, id);
      expect((await state(c, id)).knowsMinimumStock, isTrue);
      expect((await state(c, id)).variantes.first.minimumStockAtomic, isNull);
    },
    skip: skip,
  );

  test(
    'A06/A08/A11/A12/A13 HTTP: medido, máximo, parciales y bases falsas no pierden canónico',
    () async {
      final a = terminal('A'), b = terminal('B');
      final id = await create(a, measured: true, minimum: '1.5');
      await sync(a);
      await converged(a, b, id);
      expect((await state(b, id)).variantes.first.minimumStockAtomic, 1500);
      await save(
        a,
        id,
        minimum: const CambioExplicito.establecer('9007199254740.991'),
      );
      await sync(a);
      await converged(a, b, id);
      expect(
        (await state(b, id)).variantes.first.minimumStockAtomic,
        9007199254740991,
      );
      final p = (await a.tracking.products.findProductById(id))!;
      final snapshot = await state(a, id);
      for (final fault in [
        'partial',
        'mixed',
        'string',
        'boolean',
        'fraction',
        'range',
        'before',
        'version',
        'sequence',
        'event',
      ]) {
        final json = snapshot.toJson(), prior = snapshot.toJson();
        final variants = json['variants'] as List;
        if (fault == 'partial') {
          (variants.first as Map).remove('minimum_stock_atomic');
        }
        if (fault == 'mixed') {
          for (final v in variants) {
            (v as Map).remove('minimum_stock_atomic');
          }
        }
        if (fault == 'string') {
          variants.first['minimum_stock_atomic'] = '1';
        }
        if (fault == 'boolean') {
          variants.first['minimum_stock_atomic'] = true;
        }
        if (fault == 'fraction') {
          variants.first['minimum_stock_atomic'] = 0.5;
        }
        if (fault == 'range') {
          variants.first['minimum_stock_atomic'] = 9007199254740992;
        }
        if (fault == 'before') {
          (prior['product'] as Map)['name'] = 'Falso';
        }
        final e = SyncEvent(
          eventId: const Uuid().v4(),
          aggregateType: 'product',
          aggregateId: id,
          eventType: ProductoActualizadoPayload.eventType,
          deviceId: '$run-fault-$fault',
          userId: 'invalid',
          localSequence: 1,
          createdAtLocal: DateTime.now(),
          baseVersion: fault == 'version' ? p.version + 1 : p.version,
          baseServerSequence: fault == 'sequence'
              ? p.lastServerSequence! + 1
              : p.lastServerSequence,
          payload: {
            'base_event_id': fault == 'event'
                ? const Uuid().v4()
                : p.lastEventId,
            'before': prior,
            'after': json,
          },
        );
        expect(
          (await send(e))['status'],
          ['version', 'event'].contains(fault) ? 'conflict' : 'rejected',
          reason: fault,
        );
      }
      await converged(a, b, id);
      expect((await state(b, id)).toJson(), snapshot.toJson());
      final original = (await a.tracking.storedEvents())
          .where((e) => e.aggregateId == id)
          .last;
      final changed =
          jsonDecode(jsonEncode(original.payload)) as Map<String, dynamic>;
      for (final v in changed['after']['variants'] as List) {
        (v as Map).remove('minimum_stock_atomic');
      }
      expect(
        (await send(original.copyWith(payload: changed)))['status'],
        'rejected',
      );
      await converged(a, b, id);
    },
    skip: skip,
  );
}
