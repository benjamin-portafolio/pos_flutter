import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/articulos/recurso_recuperacion_resultado.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/inventory_movement_payload.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_inventario_registrado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_descartado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import '../../../support/variant_tracking_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  for (final mode in [AppMode.standalone, AppMode.serverSync]) {
    group(mode.name, () {
      late VariantTrackingHarness h;
      setUp(() => h = VariantTrackingHarness(mode: mode));
      tearDown(() async {
        await h.config.dispose();
        await h.db.close();
      });
      test(
        'el handler deriva memoria y mantiene su fuente al desvincular con historial',
        () async {
          final ids = await h.create(initial: '1');
          final original = (await h.memory.findByVariantId(ids.variantId))!;
          final resource = (await h.inventory.findItemById(ids.resourceId!))!;
          expect(resource.originVariantId, ids.variantId);
          final result = await h.save(ids.productId, ids.variantId);
          expect(result.discardedInventoryItemIds, isEmpty);
          final memory = (await h.memory.findByVariantId(ids.variantId))!;
          expect(memory.inventoryItemId, original.inventoryItemId);
          expect(memory.sourceEventId, original.sourceEventId);
          await h.save(ids.productId, ids.variantId, tracked: true);
          expect(
            (await h.products.snapshot(
              ids.productId,
            )).variantes.single.inventoryItemId,
            ids.resourceId,
          );
          expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
          expect(await h.db.select(h.db.inventoryBalances).get(), hasLength(1));
          expect(
            await h.db.select(h.db.inventoryMovements).get(),
            hasLength(1),
          );
          final refs = await h.db.select(h.db.eventRefs).get();
          expect(refs.isEmpty, mode == AppMode.standalone);
          expect(
            (await h.storedEvents()).map((e) => e.deliveryStatus).toSet(),
            {mode == AppMode.standalone ? 'not_required' : 'pending'},
          );
        },
      );
      test(
        'recupera saldo cero con historial sin repetir inicial ni balance',
        () async {
          final ids = await h.create(initial: '1');
          await h.inventoryCommands.registrarMovimiento(
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: ids.resourceId!,
              movementType: TipoMovimientoInventario.manualAdjustment,
              quantityDeltaAtomic: -1,
              movementReason: 'Ajuste',
            ),
          );
          await h.save(ids.productId, ids.variantId);
          await h.save(ids.productId, ids.variantId, tracked: true);
          expect(
            (await h.products.snapshot(
              ids.productId,
            )).variantes.single.inventoryItemId,
            ids.resourceId,
          );
          expect((await h.tracking.balanceOf(ids.resourceId!))!.isZero, true);
          expect(await h.db.select(h.db.inventoryBalances).get(), hasLength(1));
          expect(
            await h.db.select(h.db.inventoryMovements).get(),
            hasLength(2),
          );
          final count = (await h.storedEvents()).length;
          await expectLater(
            h.save(ids.productId, ids.variantId, tracked: true, initial: '2'),
            throwsFormatException,
          );
          expect((await h.storedEvents()).length, count);
        },
      );
      test(
        'legado sin memoria ni origen recupera por cadena causal completa',
        () async {
          final ids = await h.create(initial: '1');
          await h.save(ids.productId, ids.variantId);
          await h.memory.deleteByVariantId(ids.variantId);
          await (h.db.update(
            h.db.inventoryItems,
          )..where((r) => r.id.equals(ids.resourceId!))).write(
            const InventoryItemsCompanion(originVariantId: Value(null)),
          );
          await h.save(ids.productId, ids.variantId, tracked: true);
          expect(
            (await h.products.snapshot(
              ids.productId,
            )).variantes.single.inventoryItemId,
            ids.resourceId,
          );
          expect(
            (await h.memory.findByVariantId(ids.variantId))!.inventoryItemId,
            ids.resourceId,
          );
          expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
          expect(
            await h.db.select(h.db.inventoryMovements).get(),
            hasLength(1),
          );
        },
      );
      test(
        'historia incompleta requiere selección; elegir legado no crea saldo',
        () async {
          final ids = await h.create(initial: '1');
          await h.save(ids.productId, ids.variantId);
          await h.memory.deleteByVariantId(ids.variantId);
          await (h.db.update(
            h.db.inventoryItems,
          )..where((r) => r.id.equals(ids.resourceId!))).write(
            const InventoryItemsCompanion(originVariantId: Value(null)),
          );
          await (h.db.delete(
            h.db.events,
          )..where((e) => e.aggregateId.equals(ids.productId))).go();
          expect(
            await h.resolver.resolve(
              variantId: ids.variantId,
              currentInventoryItemId: null,
              requiredUnitId: InventoryUnitIds.piece,
              saleConfiguration: const UnitSaleConfiguration(),
            ),
            isA<RecursoSeleccionRequeridaResultado>(),
          );
          final candidates = await h.resolver.selectionCandidates(
            ids.variantId,
            requiredUnitId: InventoryUnitIds.piece,
            saleConfiguration: const UnitSaleConfiguration(),
          );
          expect(candidates.single.id, ids.resourceId);
          expect(candidates.single.unitName, isNotEmpty);
          expect(candidates.single.balance!.quantityOnHandAtomic, 1);
          await expectLater(
            h.save(ids.productId, ids.variantId, tracked: true),
            throwsFormatException,
          );
          await h.save(
            ids.productId,
            ids.variantId,
            tracked: true,
            selected: ids.resourceId,
          );
          expect(
            (await h.products.snapshot(
              ids.productId,
            )).variantes.single.inventoryItemId,
            ids.resourceId,
          );
          expect(await h.db.select(h.db.inventoryBalances).get(), hasLength(1));
        },
      );
      test('cadena completa nunca seguida permite su primer recurso', () async {
        final ids = await h.create(tracked: false);
        await h.save(ids.productId, ids.variantId, tracked: true);
        expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
        expect(
          await h.db.select(h.db.variantInventoryMemory).get(),
          hasLength(1),
        );
      });
      test(
        'recurso recordado faltante sin descarte válido no permite crear otro',
        () async {
          final ids = await h.create(initial: '1');
          await h.save(ids.productId, ids.variantId);
          await h.memory.deleteByVariantId(ids.variantId);
          await (h.db.delete(
            h.db.inventoryMovements,
          )..where((m) => m.inventoryItemId.equals(ids.resourceId!))).go();
          await (h.db.delete(
            h.db.inventoryItems,
          )..where((r) => r.id.equals(ids.resourceId!))).go();
          await expectLater(
            h.save(ids.productId, ids.variantId, tracked: true),
            throwsFormatException,
          );
          expect(await h.db.select(h.db.inventoryItems).get(), isEmpty);
        },
      );
      test('error al sembrar memoria revierte alta, balance y eventos', () async {
        await h.db.customStatement(
          "CREATE TRIGGER fail_memory BEFORE INSERT ON variant_inventory_memory BEGIN SELECT RAISE(ABORT, 'fixture memory failure'); END",
        );
        await expectLater(h.create(), throwsA(isA<Exception>()));
        expect(await h.db.select(h.db.events).get(), isEmpty);
        expect(await h.db.select(h.db.inventoryItems).get(), isEmpty);
        expect(await h.db.select(h.db.inventoryBalances).get(), isEmpty);
        expect(await h.db.select(h.db.products).get(), isEmpty);
        expect(await h.db.select(h.db.variantInventoryMemory).get(), isEmpty);
      });
      test(
        'venta medida conserva identidad y escala atómica al recuperar',
        () async {
          final ids = await h.create(
            initial: '1000',
            unit: InventoryUnitIds.gram,
            sale: MeasuredSaleConfiguration(
              saleUnitId: InventoryUnitIds.kilogram,
              priceReferenceQuantityAtomic: 1000,
            ),
          );
          await h.save(ids.productId, ids.variantId);
          await h.save(
            ids.productId,
            ids.variantId,
            tracked: true,
            unit: InventoryUnitIds.gram,
          );
          expect(
            (await h.products.snapshot(
              ids.productId,
            )).variantes.single.inventoryItemId,
            ids.resourceId,
          );
          expect(
            (await h.tracking.balanceOf(ids.resourceId!))!.quantityOnHandAtomic,
            1000,
          );
        },
      );
    });
  }
  group('standalone discard', () {
    late VariantTrackingHarness h;
    setUp(() => h = VariantTrackingHarness());
    tearDown(() async {
      await h.config.dispose();
      await h.db.close();
    });
    test(
      'desvinculación, descarte, repetición y reconstrucción causal real',
      () async {
        final ids = await h.create();
        final result = await h.save(ids.productId, ids.variantId);
        expect(result.discardedInventoryItemIds, [ids.resourceId]);
        expect(await h.db.select(h.db.inventoryItems).get(), isEmpty);
        expect(await h.db.select(h.db.inventoryBalances).get(), isEmpty);
        expect(await h.db.select(h.db.variantInventoryMemory).get(), isEmpty);
        expect(await h.db.select(h.db.productVariants).get(), hasLength(1));
        final events = await h.storedEvents();
        expect(events.map((e) => e.eventType), [
          RecursoInventarioCreadoPayload.eventType,
          'producto_creado',
          'producto_actualizado',
          RecursoInventarioDescartadoPayload.eventType,
        ]);
        await h.processor.apply(events.last);
        await h.processor.apply(events.first);
        expect(await h.db.select(h.db.inventoryItems).get(), isEmpty);
        await expectLater(
          h.processor.apply(
            events.first.copyWith(
              eventId: 'aaaaaaaa-0000-4000-8000-000000000001',
            ),
          ),
          throwsStateError,
        );
        final rebuilt = VariantTrackingHarness();
        addTearDown(() async {
          await rebuilt.config.dispose();
          await rebuilt.db.close();
        });
        for (final event in events) {
          final refs =
              event.eventType == RecursoInventarioDescartadoPayload.eventType
              ? RecursoInventarioDescartadoPayload.fromJson(
                  event.payload,
                ).refs(event.aggregateId)
              : [
                  LocalEventRef.affects(
                    refType: event.aggregateType,
                    refId: event.aggregateId,
                  ),
                ];
          await rebuilt.events.appendAndApply(event, refs: refs);
        }
        expect(
          await rebuilt.db.select(rebuilt.db.inventoryItems).get(),
          isEmpty,
        );
        expect(
          await rebuilt.db.select(rebuilt.db.inventoryBalances).get(),
          isEmpty,
        );
        expect(
          await rebuilt.db.select(rebuilt.db.variantInventoryMemory).get(),
          isEmpty,
        );
        expect(
          (await rebuilt.products.snapshot(ids.productId)).toJson(),
          (await h.products.snapshot(ids.productId)).toJson(),
        );
        expect(
          await rebuilt.db.select(rebuilt.db.inventoryItemDiscards).get(),
          hasLength(1),
        );
        await h.save(ids.productId, ids.variantId, tracked: true);
        expect(
          (await h.products.snapshot(
            ids.productId,
          )).variantes.single.inventoryItemId,
          isNot(ids.resourceId),
        );
      },
    );
    test('fallo SQL al borrar revierte toda la edición y el tombstone', () async {
      final ids = await h.create();
      final before = await h.products.snapshot(ids.productId);
      final memory =
          (await h.db.select(h.db.variantInventoryMemory).get()).single;
      final events = (await h.storedEvents()).length;
      await h.db.customStatement(
        "CREATE TRIGGER fail_discard AFTER DELETE ON inventory_items BEGIN SELECT RAISE(ABORT, 'fixture discard failure'); END",
      );
      await expectLater(
        h.save(ids.productId, ids.variantId),
        throwsA(isA<Exception>()),
      );
      expect(
        (await h.products.snapshot(ids.productId)).toJson(),
        before.toJson(),
      );
      expect(
        (await h.db.select(h.db.variantInventoryMemory).get()).single,
        memory,
      );
      expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
      expect(await h.db.select(h.db.inventoryBalances).get(), hasLength(1));
      expect(await h.db.select(h.db.inventoryItemDiscards).get(), isEmpty);
      expect((await h.storedEvents()).length, events);
    });
    for (final reason in [
      'unknown origin',
      'missing balance',
      'on hand',
      'available',
      'inactive',
    ]) {
      test(
        'conserva por $reason e informa el motivo después del commit',
        () async {
          final ids = await h.create();
          if (reason == 'missing balance') {
            await (h.db.delete(
              h.db.inventoryBalances,
            )..where((b) => b.inventoryItemId.equals(ids.resourceId!))).go();
          } else if (reason == 'unknown origin' || reason == 'inactive') {
            await (h.db.update(
              h.db.inventoryItems,
            )..where((r) => r.id.equals(ids.resourceId!))).write(
              reason == 'unknown origin'
                  ? const InventoryItemsCompanion(originVariantId: Value(null))
                  : const InventoryItemsCompanion(active: Value(false)),
            );
          } else {
            await (h.db.update(
              h.db.inventoryBalances,
            )..where((b) => b.inventoryItemId.equals(ids.resourceId!))).write(
              InventoryBalancesCompanion(
                quantityOnHandAtomic: Value(reason == 'on hand' ? 1 : 0),
                quantityAvailableAtomic: Value(reason == 'available' ? 1 : 0),
              ),
            );
          }
          final result = await h.save(ids.productId, ids.variantId);
          expect(result.discardedInventoryItemIds, isEmpty);
          expect(result.preservationReasons[ids.resourceId], isNotEmpty);
          expect(
            (await h.products.snapshot(
              ids.productId,
            )).variantes.single.inventoryItemId,
            isNull,
          );
          expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
          expect(
            await h.db.select(h.db.variantInventoryMemory).get(),
            hasLength(1),
          );
          expect(await h.db.select(h.db.inventoryItemDiscards).get(), isEmpty);
        },
      );
    }
    test(
      'receta de otra variante inactiva conserva referencias y recurso',
      () async {
        final ids = await h.create();
        final other = await h.create(tracked: false, name: 'Receta ajena');
        await h.save(
          other.productId,
          other.variantId,
          recipe: [
            CrearArticuloRecipeComponentCommand(
              inventoryItemId: ids.resourceId!,
              quantity: '1',
            ),
          ],
        );
        await (h.db.update(h.db.productVariants)
              ..where((v) => v.id.equals(other.variantId)))
            .write(const ProductVariantsCompanion(active: Value(false)));
        final result = await h.save(ids.productId, ids.variantId);
        expect(result.preservationReasons[ids.resourceId], contains('receta'));
        expect(await h.db.select(h.db.recipeComponents).get(), hasLength(1));
        expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
      },
    );
    test('eliminar lógicamente producto no dispara descarte', () async {
      final ids = await h.create();
      final product = (await h.products.findProductById(ids.productId))!;
      await h.commands.eliminarArticulo(
        productId: ids.productId,
        baseEventId: product.lastEventId!,
      );
      expect((await h.products.findProductById(ids.productId))!.active, false);
      expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
      expect(await h.db.select(h.db.inventoryItemDiscards).get(), isEmpty);
      expect(
        (await h.memory.findByVariantId(ids.variantId))!.inventoryItemId,
        ids.resourceId,
      );
    });
    test('la receta posterior del mismo producto impide descartar', () async {
      final ids = await h.create();
      final result = await h.save(
        ids.productId,
        ids.variantId,
        recipe: [
          CrearArticuloRecipeComponentCommand(
            inventoryItemId: ids.resourceId!,
            quantity: '1',
          ),
        ],
      );
      expect(result.discardedInventoryItemIds, isEmpty);
      expect(await h.db.select(h.db.recipeComponents).get(), hasLength(1));
      await h.save(ids.productId, ids.variantId, tracked: true);
      expect(
        (await h.products.snapshot(
          ids.productId,
        )).variantes.single.inventoryItemId,
        ids.resourceId,
      );
      expect(await h.db.select(h.db.recipeComponents).get(), isEmpty);
    });
    test(
      'otra memoria, incluso de variante inactiva, protege el recurso',
      () async {
        final ids = await h.create();
        final other = await h.create(tracked: false, name: 'Otro');
        await h.memory.upsert(
          other.variantId,
          ids.resourceId!,
          (await h.storedEvents()).last,
        );
        await (h.db.update(h.db.productVariants)
              ..where((v) => v.id.equals(other.variantId)))
            .write(const ProductVariantsCompanion(active: Value(false)));
        final result = await h.save(ids.productId, ids.variantId);
        expect(result.discardedInventoryItemIds, isEmpty);
        expect(
          result.preservationReasons[ids.resourceId],
          contains('Otra variante'),
        );
      },
    );
    test(
      'un vínculo inactivo aparecido al quitar el directo impide descarte y recuperación',
      () async {
        final ids = await h.create();
        final other = await h.create(tracked: false, name: 'Otro');
        await h.db.customStatement(
          "CREATE TRIGGER inactive_link AFTER UPDATE OF inventory_item_id ON product_variants WHEN NEW.id = '${ids.variantId}' AND OLD.inventory_item_id IS NOT NULL AND NEW.inventory_item_id IS NULL BEGIN UPDATE product_variants SET active = 0, inventory_item_id = '${ids.resourceId}' WHERE id = '${other.variantId}'; END",
        );
        final result = await h.save(ids.productId, ids.variantId);
        expect(
          result.preservationReasons[ids.resourceId],
          contains('vínculo directo'),
        );
        await expectLater(
          h.save(ids.productId, ids.variantId, tracked: true),
          throwsFormatException,
        );
        expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
      },
    );
    test('captura real de borrador protege sin event_refs', () async {
      final ids = await h.create();
      await h.drafts.agregar(
        AgregarProductoBorradorCommand(variantId: ids.variantId),
      );
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
      final result = await h.save(ids.productId, ids.variantId);
      expect(
        result.preservationReasons[ids.resourceId],
        contains('capturas de venta'),
      );
      expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
    });
    test(
      'captura inconsistente no se interpreta como autorización de borrado',
      () async {
        final ids = await h.create();
        await h.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: ids.variantId),
        );
        await h.db
            .update(h.db.saleItems)
            .write(
              const SaleItemsCompanion(
                consumptionConfigurationKey: Value('malformed'),
              ),
            );
        final before = await h.products.snapshot(ids.productId);
        await expectLater(
          h.save(ids.productId, ids.variantId),
          throwsFormatException,
        );
        expect(
          (await h.products.snapshot(ids.productId)).toJson(),
          before.toJson(),
        );
      },
    );
    test('movimiento operativo no aplicado protege el recurso', () async {
      final ids = await h.create();
      final item = (await h.inventory.findItemById(ids.resourceId!))!;
      final payload = MovimientoInventarioRegistradoPayload.create(
        baseEventId: item.lastEventId!,
        movement: InventoryMovementPayload.create(
          movementId: 'aaaaaaaa-0000-4000-8000-000000000008',
          movementType: TipoMovimientoInventario.stockReceipt,
          quantityDeltaAtomic: 1,
        ),
      );
      await h.db
          .into(h.db.events)
          .insert(
            EventsCompanion.insert(
              eventId: 'aaaaaaaa-0000-4000-8000-000000000009',
              aggregateType: 'inventory_item',
              aggregateId: ids.resourceId!,
              eventType: MovimientoInventarioRegistradoPayload.eventType,
              deviceId: 'fixture',
              userId: 'fixture',
              createdAtLocal: DateTime.utc(2026),
              payload: jsonEncode(payload.toJson()),
              applicationStatus: const Value('pending'),
              deliveryStatus: const Value('not_required'),
            ),
          );
      final result = await h.save(ids.productId, ids.variantId);
      expect(
        result.preservationReasons[ids.resourceId],
        contains('movimiento pendiente'),
      );
    });
    test('un descarte faltante o adulterado no es idempotente', () async {
      final ids = await h.create();
      await h.save(ids.productId, ids.variantId);
      final discard = (await h.storedEvents()).last;
      await expectLater(
        h.processor.apply(
          discard.copyWith(eventId: 'aaaaaaaa-0000-4000-8000-000000000020'),
        ),
        throwsStateError,
      );
      await expectLater(
        h.processor.apply(
          discard.copyWith(
            payload: {
              ...discard.payload,
              'origin_variant_id': 'aaaaaaaa-0000-4000-8000-000000000021',
            },
          ),
        ),
        throwsStateError,
      );
      await (h.db.delete(
        h.db.events,
      )..where((e) => e.eventId.equals(discard.eventId))).go();
      await expectLater(h.processor.apply(discard), throwsStateError);
    });
  });
  group('server sync undo and echo', () {
    late VariantTrackingHarness h;
    setUp(() => h = VariantTrackingHarness(mode: AppMode.serverSync));
    tearDown(() async {
      await h.config.dispose();
      await h.db.close();
    });
    test(
      'conserva autogenerado vacío y rechaza descarte remoto incluso como eco',
      () async {
        final ids = await h.create();
        await h.save(ids.productId, ids.variantId);
        expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
        expect(await h.db.select(h.db.inventoryBalances).get(), hasLength(1));
        expect(
          await h.db.select(h.db.variantInventoryMemory).get(),
          hasLength(1),
        );
        final events = await h.storedEvents();
        final payload = RecursoInventarioDescartadoPayload.create(
          baseEventId: events.first.eventId,
          triggerProductId: ids.productId,
          triggerProductEventId: events.last.eventId,
          originVariantId: ids.variantId,
        );
        final discard = events.first.copyWith(
          eventType: RecursoInventarioDescartadoPayload.eventType,
          payload: payload.toJson(),
          serverSequence: 5,
          deliveryStatus: 'delivered',
        );
        await expectLater(
          h.remote.applySyncedEvents([discard]),
          throwsStateError,
        );
        expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
        expect(
          (await h.history.eventById(discard.eventId))!.eventType,
          RecursoInventarioCreadoPayload.eventType,
        );
      },
    );
    test(
      'dos altas de origen común y edición perdedora conservan hechos cobrados',
      () async {
        final ids = await h.create(tracked: false);
        final root = (await h.storedEvents()).single;
        await h.remote.applySyncedEvents([
          root.copyWith(serverSequence: 1, deliveryStatus: 'delivered'),
        ]);
        await h.save(
          ids.productId,
          ids.variantId,
          tracked: true,
          initial: '10',
        );
        final localUpdate = (await h.storedEvents()).last;
        final localResource = (await h.products.snapshot(
          ids.productId,
        )).variantes.single.inventoryItemId!;
        await h.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: ids.variantId),
        );
        final draft = (await h.db.select(h.db.sales).get()).single;
        await h.sales.confirmar(
          ConfirmarVentaCommand(
            saleId: draft.id,
            expectedDraftEventId: draft.lastEventId!,
            expectedTotalMinor: draft.totalMinor,
            paymentMethod: 'transfer',
          ),
        );
        const officialId = 'aaaaaaaa-0000-4000-8000-000000000040';
        const officialAltaId = 'aaaaaaaa-0000-4000-8000-000000000041';
        final alta = SyncEvent(
          eventId: officialAltaId,
          aggregateType: 'inventory_item',
          aggregateId: officialId,
          eventType: RecursoInventarioCreadoPayload.eventType,
          deviceId: 'other',
          userId: 'test',
          createdAtLocal: DateTime.utc(2026),
          serverSequence: 2,
          baseVersion: 1,
          deliveryStatus: 'delivered',
          payload: RecursoInventarioCreadoPayload.create(
            inventoryItemId: officialId,
            name: 'Recurso oficial',
            defaultUnitId: InventoryUnitIds.piece,
            originVariantId: ids.variantId,
          ).toJson(),
        );
        final before = ProductoActualizadoPayload.fromJson(
          localUpdate.payload,
        ).before;
        final after = ProductoCreadoPayload.create(
          nombre: before.nombre,
          categoriaId: null,
          saleConfiguration: before.saleConfiguration,
          variantes: [
            ProductoCreadoVariante.create(
              id: ids.variantId,
              nombre: null,
              proveedores: before.variantes.single.proveedores,
              precioVentaMenor: 1000,
              costoEstandarMenor: null,
              inventoryItemId: officialId,
              orden: 0,
            ),
          ],
          dependenciasInventario: [
            const ProductoCreadoInventarioDependencia(
              refId: officialId,
              dependsOnEventId: officialAltaId,
            ),
          ],
        );
        final official = localUpdate.copyWith(
          eventId: 'aaaaaaaa-0000-4000-8000-000000000042',
          serverSequence: 3,
          deliveryStatus: 'delivered',
          payload: ProductoActualizadoPayload(
            baseEventId: root.eventId,
            before: before,
            after: after,
          ).toJson(),
        );
        await h.remote.applySyncedEvents([alta, official]);
        expect(
          (await h.history.eventById(localUpdate.eventId))!.deliveryStatus,
          'conflict',
        );
        expect(
          (await h.products.snapshot(
            ids.productId,
          )).variantes.single.inventoryItemId,
          officialId,
        );
        expect(
          (await h.memory.findByVariantId(ids.variantId))!.sourceEventId,
          official.eventId,
        );
        expect(
          (await h.memory.findByVariantId(ids.variantId))!.sourceServerSequence,
          3,
        );
        expect(
          await h.tracking.resourcesByOriginVariant(ids.variantId),
          hasLength(2),
        );
        await h.remote.applySyncedEvents([
          root.copyWith(serverSequence: 1, deliveryStatus: 'delivered'),
        ]);
        expect(
          (await h.memory.findByVariantId(ids.variantId))!.inventoryItemId,
          officialId,
        );
        expect(
          (await h.memory.findByVariantId(ids.variantId))!.sourceEventId,
          official.eventId,
        );
        expect(
          (await h.memory.findByVariantId(ids.variantId))!.sourceServerSequence,
          3,
        );

        expect(
          (await h.tracking.balanceOf(localResource))!.quantityOnHandAtomic,
          9,
        );
        expect(await h.db.select(h.db.sales).get(), hasLength(1));
        expect(await h.db.select(h.db.salePayments).get(), hasLength(1));
        expect(
          (await h.db.select(h.db.inventoryMovements).get()).where(
            (m) => m.inventoryItemId == localResource,
          ),
          hasLength(2),
        );
        await h.save(ids.productId, ids.variantId);
        await h.memory.deleteByVariantId(ids.variantId);
        await (h.db.delete(
          h.db.events,
        )..where((e) => e.aggregateId.equals(ids.productId))).go();
        expect(
          await h.resolver.resolve(
            variantId: ids.variantId,
            currentInventoryItemId: null,
            requiredUnitId: InventoryUnitIds.piece,
            saleConfiguration: const UnitSaleConfiguration(),
          ),
          isA<RecursoSeleccionRequeridaResultado>(),
        );
      },
    );
    for (final reason in [
      'inactive',
      'incompatible',
      'missing balance',
      'foreign origin',
    ]) {
      test('recuperación bloqueada por $reason no crea reemplazo', () async {
        final ids = await h.create(initial: '1');
        await h.save(ids.productId, ids.variantId);
        if (reason == 'missing balance') {
          await (h.db.delete(
            h.db.inventoryBalances,
          )..where((b) => b.inventoryItemId.equals(ids.resourceId!))).go();
        } else {
          await (h.db.update(
            h.db.inventoryItems,
          )..where((r) => r.id.equals(ids.resourceId!))).write(
            InventoryItemsCompanion(
              active: Value(reason != 'inactive'),
              defaultUnitId: Value(
                reason == 'incompatible'
                    ? InventoryUnitIds.gram
                    : InventoryUnitIds.piece,
              ),
              originVariantId: Value(
                reason == 'foreign origin'
                    ? 'aaaaaaaa-0000-4000-8000-000000000045'
                    : ids.variantId,
              ),
            ),
          );
        }
        final count = (await h.storedEvents()).length;
        await expectLater(
          h.save(ids.productId, ids.variantId, tracked: true),
          throwsFormatException,
        );
        expect((await h.storedEvents()).length, count);
        expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
      });
    }
    test('restaura exactamente la ausencia de memoria anterior', () async {
      final ids = await h.create(initial: '1');
      await h.memory.deleteByVariantId(ids.variantId);
      await h.save(ids.productId, ids.variantId);
      final event = (await h.storedEvents()).last;
      expect(await h.memory.findByVariantId(ids.variantId), isNotNull);
      final payload = ProductoActualizadoPayload.fromJson(event.payload);
      await h.products.applyUpdate(
        event,
        payload.before,
        restore: true,
        baseEventId: payload.baseEventId,
      );
      expect(await h.memory.findByVariantId(ids.variantId), isNull);
      expect(
        (await h.products.snapshot(
          ids.productId,
        )).variantes.single.inventoryItemId,
        ids.resourceId,
      );
    });
    test(
      'cadena pendiente se deshace al revés y conserva fuente confirmada por push',
      () async {
        final ids = await h.create(initial: '1');
        final created = (await h.storedEvents()).last;
        await h.save(ids.productId, ids.variantId);
        final off = (await h.storedEvents()).last;
        await h.save(ids.productId, ids.variantId, tracked: true);
        final on = (await h.storedEvents()).last;
        await h.history.updateEventSyncStatus(
          created.eventId,
          'delivered',
          serverSequence: 12,
        );
        for (final event in [on, off]) {
          final payload = ProductoActualizadoPayload.fromJson(event.payload);
          await h.products.applyUpdate(
            event,
            payload.before,
            restore: true,
            baseEventId: payload.baseEventId,
          );
        }
        final memory = (await h.memory.findByVariantId(ids.variantId))!;
        expect(memory.inventoryItemId, ids.resourceId);
        expect(memory.sourceEventId, created.eventId);
        expect(memory.sourceServerSequence, 12);
        expect(
          (await h.products.snapshot(
            ids.productId,
          )).variantes.single.inventoryItemId,
          ids.resourceId,
        );
        expect(await h.db.select(h.db.productUpdateUndo).get(), isEmpty);
      },
    );
    test(
      'pull oficial deshace cadenas y conserva la venta local ya cobrada',
      () async {
        final ids = await h.create(initial: '10');
        final roots = await h.storedEvents();
        await h.remote.applySyncedEvents([
          for (var i = 0; i < roots.length; i++)
            roots[i].copyWith(
              serverSequence: i + 1,
              deliveryStatus: 'delivered',
            ),
        ]);
        await h.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: ids.variantId),
        );
        final draft = (await h.db.select(h.db.sales).get()).single;
        await h.sales.confirmar(
          ConfirmarVentaCommand(
            saleId: draft.id,
            expectedDraftEventId: draft.lastEventId!,
            expectedTotalMinor: draft.totalMinor,
            paymentMethod: 'transfer',
          ),
        );
        await h.save(ids.productId, ids.variantId);
        final off = (await h.storedEvents()).last;
        await h.save(
          ids.productId,
          ids.variantId,
          tracked: true,
          name: 'Local posterior',
        );
        final on = (await h.storedEvents()).last;
        final official = off.copyWith(
          eventId: 'aaaaaaaa-0000-4000-8000-000000000035',
          serverSequence: 20,
          deliveryStatus: 'delivered',
        );
        await h.remote.applySyncedEvents([official]);
        expect(
          (await h.history.eventById(off.eventId))!.deliveryStatus,
          'conflict',
        );
        expect(
          (await h.history.eventById(on.eventId))!.deliveryStatus,
          'conflict',
        );
        expect(
          (await h.products.snapshot(
            ids.productId,
          )).variantes.single.inventoryItemId,
          isNull,
        );
        final memory = (await h.memory.findByVariantId(ids.variantId))!;
        expect(memory.sourceEventId, roots.last.eventId);
        expect(memory.sourceServerSequence, 2);
        expect(
          (await h.tracking.balanceOf(ids.resourceId!))!.quantityOnHandAtomic,
          9,
        );
        expect(await h.db.select(h.db.sales).get(), hasLength(1));
        expect(await h.db.select(h.db.salePayments).get(), hasLength(1));
        expect(await h.db.select(h.db.inventoryMovements).get(), hasLength(2));
        expect(await h.db.select(h.db.productUpdateUndo).get(), isEmpty);
      },
    );
    test(
      'eco antiguo no pisa memoria de una configuración posterior',
      () async {
        final ids = await h.create(initial: '1');
        final created = (await h.storedEvents()).last;
        await h.save(ids.productId, ids.variantId);
        final off = (await h.storedEvents()).last;
        // Una memoria legada acreditada al desvincular es posterior al alta.
        await h.memory.upsert(ids.variantId, ids.resourceId!, off);
        await h.remote.applySyncedEvents([
          created.copyWith(serverSequence: 8, deliveryStatus: 'delivered'),
        ]);
        final memory = (await h.memory.findByVariantId(ids.variantId))!;
        expect(memory.sourceEventId, off.eventId);
        expect(memory.sourceServerSequence, isNull);
        expect(
          (await h.products.snapshot(
            ids.productId,
          )).variantes.single.inventoryItemId,
          isNull,
        );
        await h.remote.applySyncedEvents([
          off.copyWith(serverSequence: 9, deliveryStatus: 'delivered'),
        ]);
        expect(
          (await h.memory.findByVariantId(ids.variantId))!.sourceServerSequence,
          9,
        );
      },
    );
  });
  test(
    'respaldo y restauración reales con paths aislados conservan memoria y descarte',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'seg-phase3-backup-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path,
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        await directory.delete(recursive: true);
      });
      var h = VariantTrackingHarness(database: AppDatabase());
      final kept = await h.create(initial: '1');
      await h.save(kept.productId, kept.variantId);
      final gone = await h.create(name: 'Vacío');
      await h.save(gone.productId, gone.variantId);
      final snapshot = await DriftDatabaseSnapshotService(
        db: h.db,
        stateReader: DriftDatabaseStateReader(db: h.db),
      ).createSnapshot();
      addTearDown(() => snapshot.file.parent.delete(recursive: true));
      final eventsBefore = (await h.storedEvents())
          .map((e) => e.eventId)
          .toList();
      await h.config.dispose();
      await DriftDatabaseRestoreService(
        db: h.db,
      ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
      h = VariantTrackingHarness(database: AppDatabase());
      addTearDown(() async {
        await h.config.dispose();
        await h.db.close();
      });
      expect((await h.storedEvents()).map((e) => e.eventId), eventsBefore);
      expect(
        (await h.memory.findByVariantId(kept.variantId))!.inventoryItemId,
        kept.resourceId,
      );
      expect(await h.tracking.hasAppliedDiscard(gone.resourceId!), true);
      await h.save(kept.productId, kept.variantId, tracked: true);
      expect(
        (await h.products.snapshot(
          kept.productId,
        )).variantes.single.inventoryItemId,
        kept.resourceId,
      );
      expect(await h.db.select(h.db.inventoryItems).get(), hasLength(1));
    },
  );
}
