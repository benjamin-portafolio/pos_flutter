import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_variante_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/fila_catalogo_masivo.dart';
import 'package:pos_flutter/application/edicion_masiva/resultado_operacion_masiva.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';

import '../support/product_supplier_harness.dart';
import '../support/recepcion_masiva_fixture.dart';

// Opt-in only: same isolated Nest HTTP harness used by supplier/tracking tests.
// Faults alter a test request or discard a real response; no fake acceptance.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  final url = Platform.environment['POS_BULK_SYNC_URL'];
  final skip = url == null
      ? 'Requires POS_BULK_SYNC_URL (isolated Nest/PostgreSQL).'
      : false;
  late Directory directory;
  late String run;
  final opened = <ProductSupplierHarness>[];
  setUpAll(() {
    if (url != null) {
      expect(Uri.parse(url).host, '127.0.0.1');
      expect(Platform.environment['DATABASE_HOST'], '127.0.0.1');
      expect(
        Platform.environment['DATABASE_NAME'],
        startsWith('pos_nest_test_'),
      );
    }
  });

  Future<void> assertServerStock(
    String resourceId,
    int stock,
    int receipts,
  ) async {
    final env = Platform.environment;
    final schema = env['POS_BULK_PG_SCHEMA']!;
    final database = env['DATABASE_NAME']!;
    expect(env['DATABASE_HOST'], '127.0.0.1');
    expect(database.startsWith('pos_nest_test_'), isTrue);
    expect(RegExp(r'^seg_phase3_http_[0-9]+_[0-9]+$').hasMatch(schema), isTrue);
    expect(Uuid.isValidUUID(fromString: resourceId), isTrue);
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
      database,
      '-c',
      '''SELECT json_build_object(
        'stock', (SELECT quantity_on_hand_atomic FROM "$schema".inventory_balances WHERE inventory_item_id = '$resourceId'),
        'receipts', count(*), 'bad_cost', count(total_cost_minor))
        FROM "$schema".inventory_movements WHERE inventory_item_id = '$resourceId' AND movement_type = 'stock_receipt' ''',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(result.stdout.toString()), {
      'stock': stock,
      'receipts': receipts,
      'bad_cost': 0,
    });
  }

  ProductSupplierHarness terminal(String name) {
    final h = ProductSupplierHarness(
      database: AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/$name.sqlite')),
      ),
      mode: AppMode.serverSync,
      context: LocalCommandContext(
        deviceId: '$run-$name',
        userId: 'synthetic-recepcion-s6',
      ),
    );
    opened.add(h);
    return h;
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
      expect(report.rejected, 0);
      expect(
        report.conflicts,
        0,
        reason: (await h.tracking.storedEvents())
            .where((e) => e.deliveryStatus == 'conflict')
            .map((e) => '${e.eventType}: ${e.rejectionReason}')
            .join('; '),
      );
      await h.tracking.pull(url).pullAvailableEvents(limit: 20);
    }
    expect(await h.tracking.history.pendingEvents(), isEmpty);
  }

  Future<List<FilaCatalogoMasivo>> seed(ProductSupplierHarness a) async {
    final rows = await seedRecepcion(a, nombre: 'Recepción $run');
    await sync(a);
    return [for (final f in rows) await releerRecepcion(a.db, f.clave)];
  }

  Future<ResultadoOperacionMasiva> receive(
    ProductSupplierHarness h,
    FilaCatalogoMasivo f, {
    int? venta = 2600,
    int? cantidad = 2,
    String? supplier,
  }) async {
    final c = cambioRecepcion(
      f,
      venta: venta,
      costo: supplier == null ? null : 1200,
      cantidad: cantidad,
    );
    final command = coordinadorRecepcion(h);
    final ops = await command.confirmar(
      batchId: const Uuid().v4(),
      cambios: [
        CambioVarianteMasiva(
          clave: c.clave,
          baseProducto: c.baseProducto,
          venta: c.venta,
          costo: c.costo,
          entrada: c.entrada,
          precioProveedor: supplier == null
              ? null
              : ProveedorVariante(
                  proveedorId: supplier,
                  precioInformadoMenor: 1200,
                  fechaInformadaMs: 1792281600000,
                ),
        ),
      ],
    );
    return command.ejecutar(ops.single);
  }

  Future<void> assertConverged(
    ProductSupplierHarness a,
    ProductSupplierHarness b,
    String pid,
  ) async {
    await a.tracking.pull(url!).pullAvailableEvents();
    await b.tracking.pull(url).pullAvailableEvents(limit: 2);
    expect(
      ProductoActualizadoPayload.sameState(
        await a.tracking.products.snapshot(pid),
        await b.tracking.products.snapshot(pid),
      ),
      isTrue,
    );
    final resourceIds = (await a.tracking.products.snapshot(
      pid,
    )).variantes.map((v) => v.inventoryItemId).whereType<String>();
    for (final id in resourceIds) {
      final left = await a.tracking.inventory.findBalanceByItemId(id);
      final right = await b.tracking.inventory.findBalanceByItemId(id);
      expect(right?.quantityOnHandAtomic, left?.quantityOnHandAtomic);
      expect(right?.version, left?.version);
      expect(right?.lastEventId, left?.lastEventId);
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_bulk_http_');
    run = const Uuid().v4();
  });
  tearDown(() async {
    for (final h in opened) {
      await h.dispose();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  test(
    'M43: respuesta real perdida, reapertura y mismos eventos sin duplicar entrada',
    () async {
      var a = terminal('A');
      final b = terminal('B');
      final rows = await seed(a);
      final f = rows.firstWhere((f) => f.nombreVariante == 'Piezas');
      final result = await receive(a, f);
      final client = _FaultClient(loseResponse: true);
      final push = SyncPushService(
        syncPersistence: a.tracking.history,
        endpointConfig: SyncEndpointConfig(initialBaseUrl: url!),
        conflictProjectionCleaner: a.tracking.cleaner,
        client: client,
      );
      await expectLater(push.pushPendingEvents(), throwsException);
      expect(
        (await coordinadorRecepcion(
          a,
        ).eventos(result)).every((e) => e.deliveryStatus == 'pending'),
        isTrue,
      );
      opened.remove(a);
      await a.dispose();
      a = terminal('A');
      final retryClient = _FaultClient();
      final report = await SyncPushService(
        syncPersistence: a.tracking.history,
        endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
        conflictProjectionCleaner: a.tracking.cleaner,
        client: retryClient,
      ).pushPendingEvents();
      expect(report.synced, 2);
      expect(retryClient.sentIds, client.sentIds);
      expect(retryClient.statuses, ['duplicate', 'duplicate']);
      expect(
        (await coordinadorRecepcion(a).registros()).single.resultado!.json,
        result.json,
      );
      await assertConverged(a, b, f.clave.productId);
      final movements = await b.db.select(b.db.inventoryMovements).get();
      expect(
        movements.where(
          (m) => m.movementId == result.entradas.single.movementId,
        ),
        hasLength(1),
      );
      expect(
        (await releerRecepcion(b.db, f.clave)).entrada!.existenciaAtomic,
        7,
      );
      await assertServerStock(f.entrada!.recurso.id, 7, 1);
      client.close();
      retryClient.close();
    },
    skip: skip,
  );

  test(
    'M44: proveedor y bases pendientes se entregan por dependencias existentes',
    () async {
      final a = terminal('A'), b = terminal('B');
      final rows = await seed(a);
      final sid = await a.supplier('Pendiente $run');
      final f = rows.firstWhere((f) => f.nombreVariante == 'Piezas');
      final first = await receive(a, f, supplier: sid);
      final next = await receive(
        a,
        await releerRecepcion(a.db, f.clave),
        venta: 2700,
        cantidad: 3,
        supplier: sid,
      );
      expect(
        (await coordinadorRecepcion(a).eventos(next)).last.baseServerSequence,
        isNull,
      );
      final firstPush = await a.tracking.push(url!).pushPendingEvents();
      expect(firstPush.pending, greaterThan(0));
      final firstEvents = await coordinadorRecepcion(a).eventos(first);
      expect(firstEvents.first.deliveryStatus, 'pending');
      expect(
        firstEvents.last.deliveryStatus,
        'delivered',
        reason: 'La entrada no depende artificialmente del catálogo.',
      );
      await sync(a);
      await assertConverged(a, b, f.clave.productId);
      expect(
        (await releerRecepcion(b.db, f.clave)).entrada!.existenciaAtomic,
        10,
      );
      expect(
        (await coordinadorRecepcion(
          a,
        ).eventos(next)).every((e) => e.deliveryStatus == 'delivered'),
        isTrue,
      );
    },
    skip: skip,
  );

  test(
    'M44: health real sin capability conserva lote completo pendiente e intacto',
    () async {
      final a = terminal('A');
      final rows = await seed(a);
      final sid = await a.supplier('Capability $run');
      final result = await receive(
        a,
        rows.firstWhere((f) => f.nombreVariante == 'Piezas'),
        supplier: sid,
      );
      final before = await fotoRecepcion(a.db);
      final client = _FaultClient(hideCapability: true);
      await expectLater(
        SyncPushService(
          syncPersistence: a.tracking.history,
          endpointConfig: SyncEndpointConfig(initialBaseUrl: url!),
          conflictProjectionCleaner: a.tracking.cleaner,
          client: client,
        ).pushPendingEvents(),
        throwsException,
      );
      expect(client.sentIds, isEmpty);
      expect(await fotoRecepcion(a.db), before);
      expect(
        (await coordinadorRecepcion(
          a,
        ).eventos(result)).every((e) => e.deliveryStatus == 'pending'),
        isTrue,
      );
      client.close();
      await sync(a);
    },
    skip: skip,
  );

  for (final rejectCatalog in [false, true]) {
    test(
      'M45: ${rejectCatalog ? 'catálogo rechazado/entrada aceptada' : 'catálogo aceptado/entrada rechazada'} con restauración real',
      () async {
        final a = terminal('A'), b = terminal('B');
        final rows = await seed(a);
        final f = rows.firstWhere((f) => f.nombreVariante == 'Piezas');
        final result = await receive(a, f);
        final target = rejectCatalog
            ? result.catalogEventId!
            : result.entradas.single.eventId;
        final client = _FaultClient(rejectId: target);
        final report = await SyncPushService(
          syncPersistence: a.tracking.history,
          endpointConfig: SyncEndpointConfig(initialBaseUrl: url!),
          conflictProjectionCleaner: a.tracking.cleaner,
          client: client,
        ).pushPendingEvents();
        expect(report.rejected, 1);
        expect(report.synced, 1);
        final delivery = await coordinadorRecepcion(a).eventos(result);
        expect(
          delivery.first.deliveryStatus,
          rejectCatalog ? 'rejected' : 'delivered',
        );
        expect(
          delivery.last.deliveryStatus,
          rejectCatalog ? 'delivered' : 'rejected',
        );
        // Local commit remains historical; it is not remote acceptance.
        expect(
          (await coordinadorRecepcion(a).registros()).single.resultado!.json,
          result.json,
        );
        await assertConverged(a, b, f.clave.productId);
        expect(
          (await releerRecepcion(a.db, f.clave)).entrada!.existenciaAtomic,
          rejectCatalog ? 7 : 5,
        );
        await assertServerStock(
          f.entrada!.recurso.id,
          rejectCatalog ? 7 : 5,
          rejectCatalog ? 1 : 0,
        );
        if (rejectCatalog) {
          // Resolve price only, from the restored base. Never recreate the accepted receipt.
          await receive(
            a,
            await releerRecepcion(a.db, f.clave),
            venta: 2800,
            cantidad: null,
          );
          await sync(a);
          await assertConverged(a, b, f.clave.productId);
          expect(
            (await releerRecepcion(b.db, f.clave)).entrada!.existenciaAtomic,
            7,
          );
        }
        final recorded = await coordinadorRecepcion(a).registros();
        await assertServerStock(
          f.entrada!.recurso.id,
          rejectCatalog ? 7 : 5,
          rejectCatalog ? 1 : 0,
        );
        final replay = await coordinadorRecepcion(
          a,
        ).ejecutar(recorded.first.operacion);
        expect(replay.json, result.json);
        expect((await a.tracking.history.pendingEvents()), isEmpty);
        client.close();
      },
      skip: skip,
    );
  }

  test(
    'M46: dos terminales, conflicto de catálogo y recurso; cadena restaurada sin repetir entradas',
    () async {
      final a = terminal('A'), b = terminal('B');
      final rows = await seed(a);
      final f = rows.firstWhere((f) => f.nombreVariante == 'Piezas');
      await b.tracking.pull(url!).pullAvailableEvents();
      await receive(a, f, venta: 3000, cantidad: 4);
      final losing = await receive(
        b,
        await releerRecepcion(b.db, f.clave),
        venta: 4000,
        cantidad: 2,
      );
      final chained = await receive(
        b,
        await releerRecepcion(b.db, f.clave),
        venta: 5000,
        cantidad: 3,
      );
      // Independent later product must survive restoration of the losing chain.
      final other = await seedRecepcion(b, nombre: 'Posterior $run');
      final independent = other.firstWhere((f) => f.nombreVariante == 'Piezas');
      await receive(b, independent, venta: 6000, cantidad: 1);
      await sync(a);
      await b.tracking.preflight(url).preflightPendingEvents();
      for (final result in [losing, chained]) {
        expect(
          (await coordinadorRecepcion(
            b,
          ).eventos(result)).every((e) => e.deliveryStatus == 'conflict'),
          isTrue,
        );
      }
      expect((await releerRecepcion(b.db, independent.clave)).ventaMinor, 6000);
      await sync(b);
      await assertConverged(a, b, f.clave.productId);
      expect(
        (await releerRecepcion(b.db, f.clave)).entrada!.existenciaAtomic,
        9,
      );
      // Explicit price-only resolution after conflict leaves the winner's receipt intact.
      await receive(
        b,
        await releerRecepcion(b.db, f.clave),
        venta: 3500,
        cantidad: null,
      );
      await sync(b);
      await assertConverged(a, b, f.clave.productId);
      expect(
        (await releerRecepcion(a.db, f.clave)).entrada!.existenciaAtomic,
        9,
      );
      await assertServerStock(f.entrada!.recurso.id, 9, 1);
      final stable = await fotoRecepcion(b.db);
      for (final result in [losing, chained]) {
        for (final event in await coordinadorRecepcion(b).eventos(result)) {
          await b.tracking.cleaner.hideConflictProjection(event);
        }
      }
      expect(
        await fotoRecepcion(b.db),
        stable,
        reason: 'Una restauración tardía no borra estado oficial posterior.',
      );
      expect(
        await b.db
            .customSelect('PRAGMA integrity_check')
            .map((r) => r.data.values.single)
            .getSingle(),
        'ok',
      );
      expect(
        await b.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
    skip: skip,
  );
}

class _FaultClient extends http.BaseClient {
  _FaultClient({
    this.loseResponse = false,
    this.hideCapability = false,
    this.rejectId,
  });
  final bool loseResponse;
  final bool hideCapability;
  final String? rejectId;
  final _inner = http.Client();
  final sentIds = <String>[];
  final statuses = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    var body = utf8.decode(bytes);
    if (request.url.path.endsWith('/push')) {
      final json = jsonDecode(body) as Map<String, dynamic>;
      for (final e in json['events'] as List) {
        sentIds.add(e['event_id'] as String);
        if (e['event_id'] == rejectId) e['base_version'] = 0;
      }
      body = jsonEncode(json);
    }
    final forwarded = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = body;
    final response = await http.Response.fromStream(
      await _inner.send(forwarded),
    );
    if (request.url.path.endsWith('/push')) {
      final json = jsonDecode(response.body) as Map;
      statuses.addAll(
        (json['results'] as List).map((e) => e['status'] as String),
      );
      if (loseResponse) {
        throw const SocketException(
          'Synthetic response loss after real server commit',
        );
      }
    }
    final resultBody = hideCapability && request.url.path.endsWith('/health')
        ? jsonEncode({
            ...jsonDecode(response.body) as Map,
            'capabilities': <String>[],
          })
        : response.body;
    return http.StreamedResponse(
      Stream.value(utf8.encode(resultBody)),
      response.statusCode,
      headers: {'content-type': 'application/json'},
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
