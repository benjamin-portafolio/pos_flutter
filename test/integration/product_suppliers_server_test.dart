import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_creado_payload.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/proveedores/editar_proveedor_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/sync_conflict_report_service.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_socket_listener.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/proveedores/proveedor.dart';
import '../support/product_supplier_harness.dart';

void main() {
  final url = Platform.environment['POS_SUPPLIER_SYNC_URL'];
  late String run;
  late Directory directory;
  final open = <ProductSupplierHarness>[];
  ProductSupplierHarness terminal(String name) {
    final h = ProductSupplierHarness(
      database: AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/$name.sqlite')),
      ),
      mode: AppMode.serverSync,
      context: LocalCommandContext(
        deviceId: '$run-$name',
        userId: 'synthetic-phase7',
      ),
    );
    open.add(h);
    return h;
  }

  Future<void> close(ProductSupplierHarness h) async {
    open.remove(h);
    await h.dispose();
  }

  Future<Proveedor> supplier(ProductSupplierHarness h, String id) async =>
      (await ProveedorRepositoryImpl(
        h.db.proveedorDao,
      ).watchProveedores().first).singleWhere((s) => s.id == id);
  Future<void> editSupplier(
    ProductSupplierHarness h,
    String id,
    String name,
  ) async => h.supplierCommands.editarProveedor(
    EditarProveedorCommand(
      base: await supplier(h, id),
      nombre: name,
      notas: 'nota $name',
    ),
  );
  CrearArticuloCommand article(String name, List<ProveedorVariante>? quotes) =>
      CrearArticuloCommand.conVariantes(
        nombre: name,
        variantes: [
          CrearArticuloVarianteCommand.conProveedores(
            nombre: null,
            precioVenta: '25',
            costoEstandar: '3',
            proveedores: quotes,
          ),
        ],
      );
  ProveedorVariante quote(String id, int price, [int date = 1791331200000]) =>
      ProveedorVariante(
        proveedorId: id,
        precioInformadoMenor: price,
        fechaInformadaMs: date,
      );
  Future<String> product(ProductSupplierHarness h, String supplierId) async {
    await h.commands.crearArticulo(
      article('Artículo $run', [quote(supplierId, 700)]),
    );
    return (await h.db.select(h.db.products).get()).last.id;
  }

  Future<void> editProduct(
    ProductSupplierHarness h,
    String id,
    List<ProveedorVariante>? quotes, {
    String? name,
  }) async {
    final p = (await h.tracking.products.findProductById(id))!;
    final state = await h.tracking.products.snapshot(id);
    await h.commands.actualizarArticulo(
      productId: id,
      baseEventId: p.lastEventId!,
      variantIds: state.variantes.map((v) => v.id).toList(),
      command: article(name ?? p.nombre, quotes),
    );
  }

  Future<void> sync(ProductSupplierHarness h) async {
    for (
      var i = 0;
      i < 12 && (await h.tracking.history.pendingEvents()).isNotEmpty;
      i++
    ) {
      final preflight = await h.tracking
          .preflight(url!)
          .preflightPendingEvents();
      if (preflight.requiresFullPullBeforePush) {
        await h.tracking.pull(url).pullAvailableEvents();
      }
      final pushed = await h.tracking.push(url).pushPendingEvents();
      expect(
        pushed.rejected,
        0,
        reason: (await h.tracking.storedEvents())
            .where((e) => e.deliveryStatus == 'rejected')
            .map((e) => e.rejectionReason)
            .join(', '),
      );
      expect(pushed.conflicts, 0);
      await h.tracking.pull(url).pullAvailableEvents(limit: 2);
    }
    expect(await h.tracking.history.pendingEvents(), isEmpty);
  }

  Future<Map<String, Object?>> send(SyncEvent e) async {
    final response = await http.post(
      Uri.parse('$url/sync/push'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'device_id': e.deviceId,
        'last_full_pull_server_sequence': 0,
        'events': [e.toPushJson()],
      }),
    );
    expect(response.statusCode, 201);
    return Map<String, Object?>.from(jsonDecode(response.body) as Map);
  }

  setUp(() async {
    run = const Uuid().v4();
    directory = await Directory.systemTemp.createTemp('pos_suppliers_http_');
  });
  tearDown(() async {
    for (final h in open.toList()) {
      await close(h);
    }
    await directory.delete(recursive: true);
  });
  final skip = url == null
      ? 'Requires POS_SUPPLIER_SYNC_URL with isolated NestJS/PostgreSQL.'
      : false;

  test(
    'HTTP real: alta offline, cadena causal, reinicio, ecos y terminal nueva',
    () async {
      var a = terminal('A');
      final b = terminal('B');
      final sid = await a.supplier('Proveedor $run');
      final creation = (await a.tracking.storedEvents()).single;
      await editSupplier(a, sid, 'Primera');
      final pid = await product(a, sid);
      await editProduct(a, pid, [quote(sid, 800, 1791417600000)]);
      final original = (await a.tracking.storedEvents())
          .where((e) => e.aggregateType == 'product')
          .toList();
      expect(
        ProductoCreadoPayload.fromJson(
          original.first.payload,
        ).dependenciasProveedores.single.dependsOnEventId,
        creation.eventId,
      );
      expect(
        ProductoActualizadoPayload.fromJson(
          original.last.payload,
        ).after.dependenciasProveedores.single.dependsOnEventId,
        creation.eventId,
      );
      expect(await a.db.select(a.db.eventRefs).get(), isNotEmpty);
      final offline = a.tracking.push('http://127.0.0.1:1').pushPendingEvents();
      await expectLater(offline, throwsException);
      expect(await a.tracking.history.pendingEvents(), hasLength(4));
      await close(a);
      a = terminal('A');
      final pushed = await a.tracking.push(url!).pushPendingEvents();
      expect(pushed.synced, 1);
      expect(pushed.pending, 3);
      // La confirmación del alta no sobreescribe la edición optimista posterior.
      await a.tracking.pull(url).pullAvailableEvents();
      expect((await supplier(a, sid)).nombre, 'Primera');
      expect((await supplier(a, sid)).version, 2);
      await sync(a);
      await b.tracking.pull(url).pullAvailableEvents(limit: 1);
      final state = await a.tracking.products.snapshot(pid);
      expect(
        ProductoActualizadoPayload.sameState(
          state,
          await b.tracking.products.snapshot(pid),
        ),
        isTrue,
      );
      final confirmed = (await a.tracking.storedEvents())
          .where((e) => e.aggregateId == pid)
          .toList();
      // Reintento HTTP del mismo sobre y ecos repetidos después de otra edición.
      await editProduct(a, pid, [quote(sid, 900)]);
      final optimistic = await a.tracking.products.snapshot(pid);
      final duplicate = await send(confirmed.last);
      expect((duplicate['results'] as List).single['status'], 'duplicate');
      expect(
        (duplicate['results'] as List).single['original_sync_status'],
        'synced',
      );
      await a.tracking.remote.applySyncedEvents([
        confirmed.last,
        confirmed.last,
      ]);
      expect(
        ProductoActualizadoPayload.sameState(
          optimistic,
          await a.tracking.products.snapshot(pid),
        ),
        isTrue,
      );
      await sync(a);
      await editSupplier(a, sid, 'Nombre final');
      await sync(a);
      final priceState = await a.tracking.products.snapshot(pid);
      expect(
        priceState.variantes.single.proveedores!.single.quotedPriceMinor,
        900,
      );
      await editProduct(a, pid, []);
      await sync(a);
      await b.tracking.pull(url).pullAvailableEvents();
      expect(
        (await b.tracking.products.snapshot(pid)).variantes.single.proveedores,
        isEmpty,
      );
      expect((await supplier(b, sid)).nombre, 'Nombre final');
      final c = terminal('C');
      await c.tracking.pull(url).pullAvailableEvents(limit: 2);
      expect(
        ProductoActualizadoPayload.sameState(
          await a.tracking.products.snapshot(pid),
          await c.tracking.products.snapshot(pid),
        ),
        isTrue,
      );
      expect(
        (await c.tracking.products.findProductById(pid))!.version,
        (await a.tracking.products.findProductById(pid))!.version,
      );
      expect(
        (await c.tracking.products.findProductById(pid))!.lastServerSequence,
        (await a.tracking.products.findProductById(pid))!.lastServerSequence,
      );
      expect(await c.tracking.history.pendingEvents(), isEmpty);
    },
    skip: skip,
  );

  test(
    'HTTP real: concurrencia por producto y proveedor, preflight, restauración y reporte',
    () async {
      final a = terminal('A'), b = terminal('B');
      final sid = await a.supplier('Concurrente $run');
      final pid = await product(a, sid);
      await sync(a);
      await b.tracking.pull(url!).pullAvailableEvents();
      await editProduct(a, pid, [quote(sid, 1000)]);
      await editProduct(b, pid, [quote(sid, 2000, 9007199254740991)]);
      await editProduct(b, pid, [quote(sid, 3000)], name: 'Posterior');
      final losing = (await b.tracking.history.pendingEvents())
          .map((e) => e.eventId)
          .toList();
      await sync(a);
      final pre = await b.tracking.preflight(url).preflightPendingEvents();
      expect(pre.impactingEvents, greaterThan(0));
      expect(await b.tracking.history.pendingEvents(), isEmpty);
      for (final id in losing) {
        expect(
          (await b.tracking.history.eventById(id))!.deliveryStatus,
          'conflict',
        );
      }
      expect(
        ProductoActualizadoPayload.sameState(
          await a.tracking.products.snapshot(pid),
          await b.tracking.products.snapshot(pid),
        ),
        isTrue,
      );
      final report = await SyncConflictReportService(
        syncPersistence: b.tracking.history,
        endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
      ).reportLocalConflicts();
      expect(report.conflicts, 2);
      await editSupplier(a, sid, 'Ganador');
      await editSupplier(b, sid, 'Perdedor');
      await editSupplier(b, sid, 'Segundo perdedor');
      await sync(a);
      await b.tracking.preflight(url).preflightPendingEvents();
      expect((await supplier(b, sid)).nombre, 'Ganador');
      expect(
        (await supplier(a, sid)).version,
        (await supplier(b, sid)).version,
      );
    },
    skip: skip,
  );

  test(
    'HTTP real: rechazo de alta bloquea y deshace dependientes antes de FK',
    () async {
      final a = terminal('A');
      final sid = await a.supplier('Rechazado $run');
      await editSupplier(a, sid, 'Pendiente');
      final pid = await product(a, sid);
      final root = (await a.tracking.storedEvents()).first;
      await (a.db.update(
        a.db.events,
      )..where((e) => e.eventId.equals(root.eventId))).write(
        EventsCompanion(
          payload: Value(
            jsonEncode({'name': '', 'phone': null, 'notes': null}),
          ),
        ),
      );
      final report = await a.tracking.push(url!).pushPendingEvents();
      expect(report.rejected, 1);
      expect(report.conflicts, 2);
      expect(report.pending, 0);
      expect(await a.tracking.suppliers.findById(sid), isNull);
      expect(await a.tracking.products.findProductById(pid), isNull);
      expect(await a.db.select(a.db.variantSuppliers).get(), isEmpty);
      expect(await a.tracking.history.pendingEvents(), isEmpty);
      final b = terminal('B');
      await b.tracking.pull(url).pullAvailableEvents();
      expect(await b.tracking.suppliers.findById(sid), isNull);
    },
    skip: skip,
  );

  test(
    'HTTP real: legado contra conjunto conocido y replay de ausencia histórica',
    () async {
      final a = terminal('A');
      final sid = await a.supplier('Legado $run');
      final pid = await product(a, sid);
      await sync(a);
      final current = (await a.tracking.products.findProductById(pid))!;
      final state = await a.tracking.products.snapshot(pid);
      final json = state.toJson();
      json['dependencies'] = [];
      for (final v in json['variants'] as List) {
        (v as Map).remove('suppliers');
      }
      final legacy = ProductoCreadoPayload.fromJson(json);
      final forged = SyncEvent(
        eventId: const Uuid().v4(),
        aggregateType: 'product',
        aggregateId: pid,
        eventType: ProductoActualizadoPayload.eventType,
        deviceId: '$run-old',
        userId: 'legacy',
        localSequence: 1,
        createdAtLocal: DateTime.now(),
        baseVersion: current.version,
        baseServerSequence: current.lastServerSequence,
        payload: ProductoActualizadoPayload(
          baseEventId: current.lastEventId!,
          before: legacy,
          after: legacy,
        ).toJson(),
      );
      final result = await send(forged);
      expect((result['results'] as List).single['status'], 'rejected');
      final b = terminal('B');
      await b.tracking.pull(url!).pullAvailableEvents();
      expect(
        ProductoActualizadoPayload.sameState(
          state,
          await b.tracking.products.snapshot(pid),
        ),
        isTrue,
      );
      final legacyId = const Uuid().v4();
      final created = forged.copyWith(
        eventId: const Uuid().v4(),
        aggregateId: legacyId,
        eventType: ProductoCreadoPayload.eventType,
        localSequence: 2,
        baseVersion: 1,
        payload: legacy.toJson(),
      );
      // Generar un alta legada independiente (sin bases y variantes nuevas).
      final clean = ProductoCreadoPayload.create(
        nombre: 'Histórico',
        saleConfiguration: const UnitSaleConfiguration(),
        categoriaId: null,
        variantes: [
          ProductoCreadoVariante.create(
            id: const Uuid().v4(),
            nombre: null,
            precioVentaMenor: 100,
            costoEstandarMenor: null,
            inventoryItemId: null,
            orden: 0,
          ),
        ],
      );
      final old = SyncEvent(
        eventId: created.eventId,
        aggregateType: 'product',
        aggregateId: legacyId,
        eventType: ProductoCreadoPayload.eventType,
        deviceId: created.deviceId,
        userId: 'legacy',
        localSequence: 2,
        createdAtLocal: DateTime.now(),
        baseVersion: 1,
        payload: clean.toJson(),
      );
      expect((await send(old))['results'], isNotEmpty);
      await b.tracking.pull(url).pullAvailableEvents();
      expect(
        (await b.tracking.products.snapshot(
          legacyId,
        )).variantes.single.proveedores,
        isNull,
      );
      await editProduct(b, legacyId, []);
      await sync(b);
      await a.tracking.pull(url).pullAvailableEvents();
      expect(
        (await a.tracking.products.snapshot(
          legacyId,
        )).variantes.single.proveedores,
        isEmpty,
      );
    },
    skip: skip,
  );

  test(
    'HTTP/WebSocket real: avisos, desconexión y reconexión del listener existente',
    () async {
      final a = terminal('A'), b = terminal('B');
      final socket = SyncSocketListener(
        endpointConfig: SyncEndpointConfig(initialBaseUrl: url!),
        commandContext: b.tracking.context,
        syncPersistence: b.tracking.history,
      );
      addTearDown(socket.stop);
      final connected = socket.connectionEstablished.first.timeout(
        const Duration(seconds: 10),
      );
      socket.start();
      await connected;
      final notice = socket.eventsAvailable.first.timeout(
        const Duration(seconds: 10),
      );
      final sid = await a.supplier('Socket $run');
      await sync(a);
      expect((await notice).eventTypes, contains('proveedor_creado'));
      await b.tracking.pull(url).pullAvailableEvents();
      expect(await b.tracking.suppliers.findById(sid), isNotNull);
      socket.stop();
      await editSupplier(a, sid, 'Desconectado');
      await sync(a);
      final reconnected = socket.connectionEstablished.first.timeout(
        const Duration(seconds: 10),
      );
      socket.start();
      await reconnected;
      await b.tracking.pull(url).pullAvailableEvents();
      expect((await supplier(b, sid)).nombre, 'Desconectado');
    },
    skip: skip,
  );
  test(
    'HTTP real: recetas, seguimiento, precios, fechas y venta sobreviven conflicto completo',
    () async {
      final a = terminal('A'), b = terminal('B');
      final sid = await a.supplier('Regresión $run');
      await a.tracking.inventoryCommands.crearRecurso(
        const CrearRecursoInventarioCommand(
          nombre: 'Ingrediente',
          defaultUnitId: InventoryUnitIds.piece,
          quantityDeltaAtomic: 10000,
          movementReason: 'Inicial',
        ),
      );
      final rid = (await a.db.select(a.db.inventoryItems).get()).single.id;
      await a.commands.crearArticulo(
        CrearArticuloCommand.conVariantes(
          nombre: 'Mixto',
          variantes: [
            CrearArticuloVarianteCommand.conProveedores(
              nombre: 'Directa',
              precioVenta: '25',
              costoEstandar: '3',
              inventoryUnitId: InventoryUnitIds.piece,
              initialStockQuantity: '10',
              proveedores: [quote(sid, 0, 9007199254740991)],
            ),
            CrearArticuloVarianteCommand.conProveedores(
              nombre: 'Receta',
              precioVenta: '40',
              costoEstandar: '6',
              recipeComponents: [
                CrearArticuloRecipeComponentCommand(
                  inventoryItemId: rid,
                  quantity: '2',
                ),
              ],
              proveedores: [quote(sid, 500)],
            ),
          ],
        ),
      );
      final pid = (await a.db.select(a.db.products).get()).single.id;
      final state = await a.tracking.products.snapshot(pid);
      for (final v in state.variantes) {
        await a.tracking.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: v.id),
        );
      }
      final draft = (await a.db.select(a.db.sales).get()).single;
      await a.tracking.sales.confirmar(
        ConfirmarVentaCommand(
          saleId: draft.id,
          expectedDraftEventId: draft.lastEventId!,
          expectedTotalMinor: draft.totalMinor,
          paymentMethod: 'transfer',
        ),
      );
      await sync(a);
      await b.tracking.pull(url!).pullAvailableEvents();
      final sales = await a.db.select(a.db.sales).get();
      final lines = await a.db.select(a.db.saleItems).get();
      final movements = await a.db.select(a.db.inventoryMovements).get();
      final balances = await a.db.select(a.db.inventoryBalances).get();
      Future<void> change(
        ProductSupplierHarness h,
        int price, {
        bool recipe = true,
      }) async {
        final p = (await h.tracking.products.findProductById(pid))!;
        final current = await h.tracking.products.snapshot(pid);
        await h.commands.actualizarArticulo(
          productId: pid,
          baseEventId: p.lastEventId!,
          variantIds: current.variantes.map((v) => v.id).toList(),
          command: CrearArticuloCommand.conVariantes(
            nombre: p.nombre,
            variantes: [
              for (final v in current.variantes)
                CrearArticuloVarianteCommand.conProveedores(
                  nombre: v.nombre,
                  precioVenta: v.precioVentaMenor == 2500 ? '25' : '40',
                  costoEstandar: v.costoEstandarMenor == 300 ? '3' : '6',
                  inventoryUnitId: v.inventoryItemId == null
                      ? null
                      : InventoryUnitIds.piece,
                  existingInventoryItemId: v.inventoryItemId,
                  recipeComponents: recipe
                      ? [
                          for (final c in v.componentesReceta)
                            CrearArticuloRecipeComponentCommand(
                              inventoryItemId: c.inventoryItemId,
                              quantity: c.quantityAtomic.toString(),
                            ),
                        ]
                      : [],
                  proveedores: [quote(sid, price, 9007199254740991)],
                ),
            ],
          ),
        );
      }

      await change(a, 9007199254740991);
      await change(b, 900, recipe: false);
      await change(b, 1000, recipe: false);
      await sync(a);
      await b.tracking.preflight(url).preflightPendingEvents();
      expect(
        ProductoActualizadoPayload.sameState(
          await a.tracking.products.snapshot(pid),
          await b.tracking.products.snapshot(pid),
        ),
        isTrue,
      );
      expect(
        (await b.tracking.products.snapshot(
          pid,
        )).variantes.last.componentesReceta,
        hasLength(1),
      );
      expect(
        (await b.tracking.products.snapshot(
          pid,
        )).variantes.first.inventoryItemId,
        state.variantes.first.inventoryItemId,
      );
      for (final h in [a, b]) {
        final current = await h.tracking.products.snapshot(pid);
        expect(
          current.variantes.map((v) => v.proveedores!.single.quotedAtMs),
          everyElement(9007199254740991),
        );
        expect(current.variantes.map((v) => v.costoEstandarMenor), [300, 600]);
      }
      expect(await a.db.select(a.db.sales).get(), sales);
      expect(await a.db.select(a.db.saleItems).get(), lines);
      expect(await a.db.select(a.db.inventoryMovements).get(), movements);
      expect(await a.db.select(a.db.inventoryBalances).get(), balances);
      expect(
        (await b.db.select(b.db.sales).get())
            .singleWhere((s) => s.id == draft.id)
            .totalMinor,
        sales.singleWhere((s) => s.id == draft.id).totalMinor,
      );
      expect(
        (await b.db.select(b.db.inventoryMovements).get())
            .where((m) => movements.any((a) => a.movementId == m.movementId))
            .length,
        movements.length,
      );
      expect(
        (await b.db.select(b.db.inventoryBalances).get())
            .where(
              (x) =>
                  balances.any((a) => a.inventoryItemId == x.inventoryItemId),
            )
            .map((x) => x.quantityOnHandAtomic)
            .toSet(),
        balances.map((x) => x.quantityOnHandAtomic).toSet(),
      );
    },
    skip: skip,
  );

  test(
    'HTTP real: alta oficial colisiona con alta offline y restaura cadena inversa',
    () async {
      final a = terminal('A');
      final sid = await a.supplier('Local');
      await editSupplier(a, sid, 'Local posterior');
      final pid = await product(a, sid);
      final official = SyncEvent(
        eventId: const Uuid().v4(),
        aggregateType: 'supplier',
        aggregateId: sid,
        eventType: ProveedorCreadoPayload.eventType,
        deviceId: '$run-other',
        userId: 'synthetic',
        localSequence: 1,
        createdAtLocal: DateTime.now(),
        baseVersion: 1,
        payload: ProveedorCreadoPayload(name: 'Oficial').toJson(),
      );
      expect((await send(official))['results'], isNotEmpty);
      await a.tracking.preflight(url!).preflightPendingEvents();
      expect((await supplier(a, sid)).nombre, 'Oficial');
      expect(await a.tracking.products.findProductById(pid), isNull);
      expect(await a.tracking.history.pendingEvents(), isEmpty);
      expect(
        (await a.tracking.storedEvents()).where(
          (e) => e.deliveryStatus == 'conflict',
        ),
        hasLength(3),
      );
    },
    skip: skip,
  );

  test(
    'HTTP real: rechazo de base de producto retira ediciones dependientes y restaura oficial',
    () async {
      final a = terminal('A');
      final sid = await a.supplier('Base');
      final pid = await product(a, sid);
      await sync(a);
      final before = await a.tracking.products.snapshot(pid);
      final official = (await a.tracking.products.findProductById(pid))!;
      await editProduct(a, pid, [quote(sid, 900)]);
      final root = (await a.tracking.history.pendingEvents()).single;
      await editProduct(a, pid, [quote(sid, 1000)]);
      await (a.db.update(a.db.events)
            ..where((e) => e.eventId.equals(root.eventId)))
          .write(const EventsCompanion(baseVersion: Value(0)));
      final report = await a.tracking.push(url!).pushPendingEvents();
      expect(report.rejected, 1);
      expect(report.conflicts, 1);
      expect(
        ProductoActualizadoPayload.sameState(
          before,
          await a.tracking.products.snapshot(pid),
        ),
        isTrue,
      );
      expect(await a.tracking.history.pendingEvents(), isEmpty);
      expect(
        (await a.tracking.products.findProductById(pid))!.lastServerSequence,
        official.lastServerSequence,
      );
      expect(
        (await a.tracking.products.findProductById(pid))!.version,
        official.version,
      );
      final b = terminal('B');
      await b.tracking.pull(url).pullAvailableEvents();
      expect(
        ProductoActualizadoPayload.sameState(
          before,
          await b.tracking.products.snapshot(pid),
        ),
        isTrue,
      );
    },
    skip: skip,
  );
  test(
    'HTTP/PostgreSQL real: evento futuro detiene página completa y conserva cursor',
    () async {
      final schema = Platform.environment['POS_SUPPLIER_PG_SCHEMA']!;
      final database = Platform.environment['DATABASE_NAME']!;
      expect(
        RegExp(r'^seg_phase3_http_[0-9]+_[0-9]+$').hasMatch(schema),
        isTrue,
      );
      expect(database.startsWith('pos_nest_test_'), isTrue);
      expect(Platform.environment['DATABASE_HOST'], '127.0.0.1');
      Future<void> sql(String command) async {
        final result = await Process.run('psql', [
          '-X',
          '-v',
          'ON_ERROR_STOP=1',
          '-h',
          '127.0.0.1',
          '-p',
          Platform.environment['DATABASE_PORT']!,
          '-U',
          Platform.environment['DATABASE_USER']!,
          '-d',
          database,
          '-c',
          command,
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
      }

      final a = terminal('A'), b = terminal('B');
      await b.tracking.pull(url!).pullAvailableEvents();
      final cursor = await b.tracking.history.lastFullPullServerSequence();
      final sid = await a.supplier('Página atómica $run');
      final report = await a.tracking.push(url).pushPendingEvents();
      expect(report.synced, 1);
      final poison = const Uuid().v4();
      try {
        await sql(
          "INSERT INTO \"$schema\".events(event_id,aggregate_type,aggregate_id,event_type,device_id,user_id,created_at_local,payload,sync_status) VALUES ('$poison','supplier','$poison','future_supplier_event','synthetic-future','test',now(),'{}','synced')",
        );
        await expectLater(
          b.tracking.pull(url).pullAvailableEvents(),
          throwsUnsupportedError,
        );
        expect(await b.tracking.history.lastFullPullServerSequence(), cursor);
        expect(await b.tracking.suppliers.findById(sid), isNull);
        expect(await b.tracking.history.eventById(poison), isNull);
      } finally {
        await sql("DELETE FROM \"$schema\".events WHERE event_id='$poison'");
      }
      await b.tracking.pull(url).pullAvailableEvents();
      expect(await b.tracking.suppliers.findById(sid), isNotNull);
      expect(
        await b.tracking.history.lastFullPullServerSequence(),
        greaterThan(cursor),
      );
    },
    skip: skip,
  );
}
