import 'package:pos_flutter/application/sync/payloads/abono_cliente_registrado_payload.dart';
import 'package:pos_flutter/application/sync/handlers/abono_cliente_event_handler.dart';
import 'package:pos_flutter/data/local/drift/drift_customer_credit_store.dart';
import 'package:pos_flutter/application/commands/caja/caja_command_service.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/anular_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/registrar_devolucion_venta_command.dart';
import 'package:pos_flutter/application/sync/models/sale_adjustment_outcome.dart';
import 'package:pos_flutter/application/sync/payloads/venta_anulada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/devolucion_venta_registrada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/caja_abierta_payload.dart';
import 'package:pos_flutter/application/sync/payloads/caja_cerrada_payload.dart';
import 'package:pos_flutter/application/sync/handlers/cash_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_confirmada_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/sale_adjustment_event_handler.dart';
import 'package:pos_flutter/data/local/drift/drift_cash_projection_store.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/sale_adjustment_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_contract.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sale_adjustment_store.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

Map<String, Object?> object(Object? v) => Map<String, Object?>.from(v as Map);
List<Map<String, Object?>> adjustmentFixtures() =>
    ((jsonDecode(File('contracts/sale_adjustments/v1.json').readAsStringSync())
                as Map)['cases']
            as List)
        .map(object)
        .toList();

class SaleAdjustmentHarness {
  SaleAdjustmentHarness(this.db, this.directory);
  final AppDatabase db;
  final Directory directory;
  final config = AppConfigController(
    AppConfig.initial.copyWith(mode: AppMode.standalone, cashEnabled: false),
  );
  late final store = DriftSaleAdjustmentStore(db);
  static Future<SaleAdjustmentHarness> create() async {
    final dir = await Directory.systemTemp.createTemp('pos-adjustment-');
    return SaleAdjustmentHarness(
      AppDatabase.forTesting(NativeDatabase(File('${dir.path}/test.sqlite'))),
      dir,
    );
  }

  DriftLocalEventStore events(Future<void> Function(SyncEvent) handler) =>
      DriftLocalEventStore(
        db: db,
        eventDao: db.eventDao,
        eventRefDao: db.eventRefDao,
        appConfigController: config,
        eventProcessor: EventProcessor(
          handlers: {
            AbonoClienteRegistradoPayload.eventType: AbonoClienteEventHandler(
              DriftCustomerCreditStore(db),
              cash: cash,
            ).apply,
            'venta_anulada': handler,
            'devolucion_venta_registrada': handler,
            CajaAbiertaPayload.eventType: cash.apply,
            CajaCerradaPayload.eventType: cash.apply,
            VentaConfirmadaPayload.eventType: (e) =>
                VentaConfirmadaEventHandler(
                  DriftConfirmedSaleStore(db),
                  cash: cash,
                ).apply(e),
          },
        ),
      );

  final context = const LocalCommandContext(
    userId: 'operator',
    deviceId: 'terminal',
  );
  late final cashStore = DriftCashProjectionStore(db);
  late final cash = CashEventHandler(cashStore);
  late final handler = SaleAdjustmentEventHandler(
    store: store,
    cash: cashStore,
    config: config,
  );
  SaleAdjustmentCommandService service({
    Future<void> Function(SyncEvent)? apply,
  }) => SaleAdjustmentCommandService(
    store: store,
    events: events(apply ?? handler.apply),
    config: config,
    context: context,
  );
  Future<SaleAdjustmentOutcome> execute(
    Map<String, Object?> j, {
    SaleAdjustmentCommandService? commands,
  }) {
    final c = commands ?? service();
    return j['kind'] == 'void'
        ? c.anular(
            AnularVentaCommand(
              payload: VentaAnuladaPayload.fromJson(j),
              userId: 'operator',
              deviceId: 'terminal',
            ),
          )
        : c.devolver(
            RegistrarDevolucionVentaCommand(
              payload: DevolucionVentaRegistradaPayload.fromJson(j),
              userId: 'operator',
              deviceId: 'terminal',
            ),
          );
  }

  Future<void> open(String id, String eventId) async {
    config.update(config.config.copyWith(cashEnabled: true));
    final previous = await cashStore.latest('terminal');
    final p = CajaAbiertaPayload(
      openingMinor: 0,
      openedAtMs: 1793100000000,
      previousCloseEventId: previous?.lastEventId,
    );
    await events(handler.apply).appendAndApply(
      SyncEvent(
        eventId: eventId,
        aggregateType: CajaAbiertaPayload.aggregateType,
        aggregateId: id,
        eventType: CajaAbiertaPayload.eventType,
        baseVersion: 1,
        deviceId: 'terminal',
        userId: 'operator',
        createdAtLocal: DateTime.fromMillisecondsSinceEpoch(
          p.openedAtMs,
          isUtc: true,
        ),
        payload: p.toJson(),
      ),
      refs: [LocalEventRef.affects(refType: 'cash_session', refId: id)],
    );
  }

  Future<void> seed(Map<String, Object?> fixture) async {
    final p = VentaConfirmadaPayload.fromJson(object(fixture['original']));
    final a = object(fixture['payload']);
    if (p.cash != null) await open(p.cash!.sessionId, p.cash!.openingEventId);
    for (final l in p.lines) {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: l.productId,
              name: 'Catálogo cambiado',
              active: const Value(false),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: l.snapshot.variantId,
              productId: l.productId,
              salePriceMinor: 999999,
              sortOrder: 0,
              active: const Value(false),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      for (final c in l.consumptions) {
        await db
            .into(db.inventoryItems)
            .insert(
              InventoryItemsCompanion.insert(
                id: c.inventoryItemId,
                defaultUnitId: InventoryUnitIds.piece,
                name: 'Recurso inactivo',
                active: const Value(false),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await db
            .into(db.inventoryBalances)
            .insert(
              InventoryBalancesCompanion.insert(
                inventoryItemId: c.inventoryItemId,
                quantityOnHandAtomic: 100000,
                quantityAvailableAtomic: 100000,
                lastEventId: 'seed',
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
    if (p.clienteId != null) {
      await db
          .into(db.clientes)
          .insert(
            ClientesCompanion.insert(
              id: p.clienteId!,
              nombre: 'Cliente',
              createdEventId: Value(p.clienteEventId),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    final e = SyncEvent(
      eventId: a['confirmation_event_id'] as String,
      aggregateType: 'sale',
      aggregateId: a['sale_id'] as String,
      eventType: VentaConfirmadaPayload.eventType,
      deviceId: 'terminal',
      userId: 'operator',
      createdAtLocal: DateTime.fromMillisecondsSinceEpoch(
        1793100000000,
        isUtc: true,
      ),
      baseVersion: 1,
      payload: p.toJson(),
    );
    await events((_) async {}).appendAndApply(
      e,
      refs: [LocalEventRef.affects(refType: 'sale', refId: e.aggregateId)],
    );
    if (p.cash != null) {
      await CajaCommandService(
        store: cashStore,
        events: events(handler.apply),
        context: context,
        config: config,
      ).cerrar(
        CerrarCajaCommand(
          sessionId: p.cash!.sessionId,
          countedMinor: p.totalMinor,
        ),
      );
    }
    final cashContext = fixture['cash_context'] == null
        ? null
        : object(fixture['cash_context']);
    config.update(
      config.config.copyWith(
        cashEnabled:
            cashContext?['enabled'] as bool? ??
            object(a['settlement'])['cash_enabled'] as bool,
      ),
    );
    if (cashContext?['session_id'] != null) {
      await open(
        cashContext!['session_id'] as String,
        cashContext['opening_event_id'] as String,
      );
      if (cashContext['open'] != true) {
        await CajaCommandService(
          store: cashStore,
          events: events(handler.apply),
          context: context,
          config: config,
        ).cerrar(
          CerrarCajaCommand(
            sessionId: cashContext['session_id'] as String,
            countedMinor: 0,
          ),
        );
      }
    }
  }

  LocalEventAppend prepare(
    Map<String, Object?> fixture, {
    SaleAdjustmentPayload? payload,
    List<SaleAdjustmentPayload>? history,
  }) {
    final p =
        payload ?? SaleAdjustmentPayload.fromJson(object(fixture['payload']));
    return SaleAdjustmentCommandContract.prepare(
      payload: p,
      original: VentaConfirmadaPayload.fromJson(object(fixture['original'])),
      saleId: p.saleId,
      confirmationEventId: p.confirmationEventId,
      history:
          history ??
          (fixture['history'] as List)
              .map((e) => SaleAdjustmentPayload.fromJson(object(e)))
              .toList(),
      mode: 'standalone',
      userId: 'operator',
      deviceId: 'terminal',
    );
  }

  Future<void> replayHistory(Map<String, Object?> fixture) async {
    final savedConfig = config.config;
    for (final raw in fixture['history'] as List) {
      final j = object(raw);
      final p = SaleAdjustmentPayload.fromJson(j);
      final b = p.settlement.cash;
      if (b != null && await cashStore.find(b.sessionId) == null) {
        await open(b.sessionId, b.openingEventId);
      }
      config.update(
        config.config.copyWith(cashEnabled: p.settlement.cashEnabled),
      );
      await execute(j);
    }
    config.update(savedConfig);
  }

  Future<void> creditWithPayment(Map<String, Object?> fixture) async {
    final original = VentaConfirmadaPayload.fromJson(
      object(fixture['original']),
    );
    // Otra deuda confirmada, con identidades independientes y el mismo cliente.
    final other = object(jsonDecode(jsonEncode(fixture)));
    final o = object(other['original']);
    final lines = (o['lines'] as List).map(object).toList();
    for (final line in lines) {
      line['sale_item_id'] = '00000000-0000-4000-8000-000000000902';
      for (final c in line['consumptions'] as List) {
        if (c['movement_id'] != null) {
          c['movement_id'] = '00000000-0000-4000-8000-000000000903';
        }
      }
    }
    o['lines'] = lines;
    o['occurred_at_ms'] = original.occurredAtMs! + 1;
    other['original'] = o;
    other['payload'] = {
      ...object(other['payload']),
      'sale_id': '00000000-0000-4000-8000-000000000900',
      'confirmation_event_id': '00000000-0000-4000-8000-000000000901',
    };
    await seed(other);
    final p = AbonoClienteRegistradoPayload(
      clienteId: original.clienteId!,
      clienteEventId: original.clienteEventId!,
      amountMinor: 1500,
      method: 'transfer',
      occurredAtMs: original.occurredAtMs! + 2,
    );
    await events(handler.apply).appendAndApply(
      SyncEvent(
        eventId: '00000000-0000-4000-8000-000000000905',
        aggregateType: AbonoClienteRegistradoPayload.aggregateType,
        aggregateId: '00000000-0000-4000-8000-000000000904',
        eventType: AbonoClienteRegistradoPayload.eventType,
        deviceId: 'terminal',
        userId: 'operator',
        createdAtLocal: DateTime.fromMillisecondsSinceEpoch(
          p.occurredAtMs,
          isUtc: true,
        ),
        baseVersion: 1,
        payload: p.toJson(),
      ),
      refs: p.refs('00000000-0000-4000-8000-000000000904'),
    );
  }

  Future<String> snapshot() async => jsonEncode({
    for (final t in [
      'events',
      'event_refs',
      'sales',
      'sale_items',
      'sale_payments',
      'sale_adjustments',
      'sale_adjustment_lines',
      'inventory_movements',
      'inventory_balances',
      'cash_sessions',
      'cash_movements',
      'credit_sales',
      'customer_payments',
      'sale_credit_reductions',
      'credit_allocations',
    ])
      t: (await db.customSelect('SELECT * FROM $t ORDER BY rowid').get())
          .map((r) => r.data)
          .toList(),
  });
  Future<void> close() async {
    await db.close();
    await config.dispose();
    await directory.delete(recursive: true);
  }
}
