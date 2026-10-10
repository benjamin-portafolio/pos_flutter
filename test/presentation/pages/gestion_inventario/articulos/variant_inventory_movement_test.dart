import 'package:pos_flutter/data/local/drift/drift_variant_inventory_tracking_store.dart';
import 'package:pos_flutter/data/local/drift/drift_variant_inventory_memory_store.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/inventario/editar_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/inventario/inventory_command_service.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_preview_form.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/inventory_article_card.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/recursos/inventory_movement_screen.dart';

void main() {
  late _Fixture fixture;
  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.db.close());

  for (final existing in [false, true]) {
    testWidgets(
      'captura inicial ${existing ? 'al activar por primera vez' : 'en alta'} se guarda con el producto',
      (tester) async {
        if (existing) await fixture.createArticle(tracking: false);
        await fixture.pump(tester);
        if (existing) {
          await _tap(tester, find.byType(InventoryArticleCard));
        } else {
          await _tap(tester, find.byTooltip('Agregar'));
          await _tap(tester, find.byKey(const Key('add_article_option')));
          await tester.enterText(
            find.byKey(const Key('article_name_field')),
            'Agua',
          );
          await tester.enterText(
            find.byKey(const Key('article_price_field')),
            '10',
          );
          await _tap(tester, find.text('Avanzado'));
        }
        await _openVariant(tester);
        await _tap(
          tester,
          find.byKey(const Key('variant_inventory_tracking_switch')),
        );
        expect(
          find.byKey(const Key('variant_initial_stock_field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('register_inventory_movement_button')),
          findsNothing,
        );
        await tester.enterText(
          find.byKey(const Key('variant_initial_stock_field')),
          '7',
        );
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        expect(
          await fixture.db.select(fixture.db.inventoryItems).get(),
          isEmpty,
        );
        await _tap(tester, find.byKey(const Key('save_article_button')));
        expect(
          (await fixture.db.select(fixture.db.inventoryBalances).get())
              .single
              .quantityOnHandAtomic,
          7,
        );
        expect(
          (await fixture.db.select(fixture.db.inventoryMovements).get())
              .single
              .movementType,
          'initial_balance',
        );
        expect(
          (await fixture.db.select(fixture.db.productVariants).get())
              .single
              .inventoryItemId,
          isNotNull,
        );
        await fixture.unmount(tester);
      },
    );
  }

  testWidgets(
    'vínculo con saldo cero: cancelar movimiento no registra eventos',
    (tester) async {
      await fixture.createArticle();
      await fixture.pump(tester);
      await _tap(tester, find.byType(InventoryArticleCard));
      await _openVariant(tester);
      expect(
        find.byKey(const Key('variant_initial_stock_field')),
        findsNothing,
      );
      expect(find.text('0 pza'), findsOneWidget);
      final eventsBefore = await fixture.db.select(fixture.db.events).get();
      await _openMovement(tester);
      expect(
        find.byKey(const Key('inventory_resource_name_field')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('inventory_default_unit_field')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('inventory_initial_quantity_field')),
        '3',
      );
      await _tap(
        tester,
        find.byKey(const Key('close_inventory_movement_button')),
      );
      await _tap(
        tester,
        find.byKey(const Key('discard_inventory_movement_button')),
      );
      expect(find.byKey(const Key('variant_editor_screen')), findsOneWidget);
      expect(
        await fixture.db.select(fixture.db.events).get(),
        hasLength(eventsBefore.length),
      );
      expect(
        await fixture.db.select(fixture.db.inventoryMovements).get(),
        isEmpty,
      );
      await fixture.unmount(tester);
    },
  );

  testWidgets(
    'registro permanece al cancelar variante y producto; no renombra un recurso actualizado',
    (tester) async {
      await fixture.createArticle();
      await fixture.pump(tester);
      await _tap(tester, find.byType(InventoryArticleCard));
      await tester.enterText(
        find.byKey(const Key('article_name_field')),
        'Cambio sin guardar',
      );
      await _openVariant(tester);
      await tester.enterText(
        find.byKey(const Key('variant_name_field')),
        'Otro nombre sin guardar',
      );
      final itemId = await fixture.itemId;
      // El nombre cambia después de abrir el formulario: el nuevo acceso debe
      // usar solo el delta, sin enviar los datos antiguos del editor.
      await fixture.inventory.editarRecurso(
        EditarRecursoInventarioCommand(
          inventoryItemId: itemId,
          nombre: 'Recurso vigente',
        ),
      );
      await _openMovement(tester);
      expect(find.text('Recurso vigente'), findsOneWidget);
      expect(
        find.byKey(const Key('inventory_movement_independent_note')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('inventory_initial_quantity_field')),
        '4',
      );
      await _tap(
        tester,
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(find.byKey(const Key('variant_editor_screen')), findsOneWidget);
      expect(find.text('4 pza'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('close_variant_editor_button')));
      await _tap(tester, find.byTooltip('Cancelar'));
      await _tap(tester, find.text('DESCARTAR'));
      expect(
        (await fixture.db.select(fixture.db.products).get()).single.name,
        'Agua',
      );
      expect(
        (await fixture.db.select(fixture.db.productVariants).get()).single.name,
        'Grande',
      );
      expect(
        (await fixture.db.select(fixture.db.inventoryItems).get()).single.name,
        'Recurso vigente',
      );
      expect(
        (await fixture.db.select(fixture.db.inventoryItems).get())
            .single
            .defaultUnitId,
        InventoryUnitIds.piece,
      );
      expect(
        (await fixture.db.select(fixture.db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        4,
      );
      expect(
        await fixture.db.select(fixture.db.inventoryMovements).get(),
        hasLength(1),
      );
      final events = await fixture.db.select(fixture.db.events).get();
      expect(
        events.where((event) => event.eventType == 'producto_actualizado'),
        isEmpty,
      );
      expect(
        events.where(
          (event) => event.eventType == 'recurso_inventario_actualizado',
        ),
        hasLength(1),
      );
      expect(
        events.where(
          (event) => event.eventType == 'movimiento_inventario_registrado',
        ),
        hasLength(1),
      );
      expect(
        events.every((event) => event.deliveryStatus == 'not_required'),
        isTrue,
      );
      expect(await fixture.db.select(fixture.db.eventRefs).get(), isEmpty);
      await fixture.unmount(tester);
    },
  );

  testWidgets(
    'saldo vigente, corrección con motivo, delta negativo y seguimiento desactivado',
    (tester) async {
      await fixture.createArticle();
      await fixture.pump(tester);
      await _tap(tester, find.byType(InventoryArticleCard));
      await _openVariant(tester);
      await _openMovement(tester);
      // Vacío y cero deben validar sin lanzar desde readDraft.
      await _tap(
        tester,
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(find.text('Indica la cantidad del movimiento.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('inventory_initial_quantity_field')),
        '0',
      );
      await _tap(
        tester,
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(tester.takeException(), isNull);
      expect(
        await fixture.db.select(fixture.db.inventoryMovements).get(),
        isEmpty,
      );
      await _tap(tester, find.text('Corregir existencia'));
      await _tap(tester, find.text('Disminuir (−)'));
      await tester.enterText(
        find.byKey(const Key('inventory_initial_quantity_field')),
        '5',
      );
      await _tap(
        tester,
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(
        find.text('Selecciona un motivo para la corrección manual.'),
        findsOneWidget,
      );
      // Otro movimiento ocurre mientras está abierta la pantalla.
      await fixture.inventory.registrarMovimiento(
        RegistrarMovimientoInventarioCommand(
          inventoryItemId: await fixture.itemId,
          movementType: TipoMovimientoInventario.stockReceipt,
          quantityDeltaAtomic: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 pza'), findsOneWidget);
      expect(find.text('−3 pza'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const Key('inventory_movement_reason_choice')),
      );
      await _tap(tester, find.text('Conteo físico').last);
      await _tap(
        tester,
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(find.text('−3 pza'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const Key('variant_inventory_tracking_switch')),
      );
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      await _tap(tester, find.byKey(const Key('save_article_button')));
      expect(
        (await fixture.db.select(fixture.db.productVariants).get())
            .single
            .inventoryItemId,
        isNull,
      );
      expect(
        await fixture.db.select(fixture.db.inventoryItems).get(),
        hasLength(1),
      );
      expect(
        (await fixture.db.select(fixture.db.inventoryBalances).get())
            .single
            .quantityOnHandAtomic,
        -3,
      );
      final movements = await fixture.db
          .select(fixture.db.inventoryMovements)
          .get();
      expect(movements, hasLength(2));
      expect(
        movements
            .singleWhere((m) => m.movementType == 'manual_adjustment')
            .reason,
        'Conteo físico',
      );
      await fixture.unmount(tester);
    },
  );

  testWidgets('consulta conserva saldo y no permite registrar movimientos', (
    tester,
  ) async {
    await fixture.createArticle();
    final detail = (await fixture.products.obtenerDetalle(
      (await fixture.db.select(fixture.db.products).get()).single.id,
    ))!;
    final resources = await fixture.resources.watchRecursos().first;
    // Abrir explícitamente un formulario sin onSave establece modo consulta.
    await tester.pumpWidget(
      MaterialApp(
        home: ArticleFormScreen(
          categorias: const [],
          unidadesVenta: await fixture.units.obtenerUnidadesActivas(),
          initialValue: ArticuloPreviewForm.fromDetalle(detail, resources),
          inventoryResourceRepository: fixture.resources,
          onRegisterInventoryMovement: (_, _) async =>
              fail('No debe registrar en consulta'),
        ),
      ),
    );
    await _openVariant(tester);
    expect(find.text('0 pza'), findsOneWidget);
    expect(
      find.byKey(const Key('register_inventory_movement_button')),
      findsNothing,
    );
    await fixture.unmount(tester);
  });

  testWidgets(
    'bloquea doble registro y cierre mientras guarda; permite reintentar errores',
    (tester) async {
      await fixture.createArticle();
      final gate = Completer<void>();
      var calls = 0;
      var failSave = true;
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryMovementScreen(
            repository: fixture.resources,
            inventoryItemId: await fixture.itemId,
            resourceLabel: 'Agua · Grande',
            onRegister: (movement) async {
              calls++;
              if (failSave) throw StateError('Error local');
              await gate.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('inventory_initial_quantity_field')),
        '4',
      );
      await _tap(
        tester,
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(
        find.byKey(const Key('inventory_movement_save_error')),
        findsOneWidget,
      );
      failSave = false;
      await tester.tap(
        find.byKey(const Key('register_inventory_movement_button')),
      );
      await tester.pump();
      final button = tester.widget<TextButton>(
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(button.onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('close_inventory_movement_button')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const Key('register_inventory_movement_button')),
      );
      await tester.pump();
      expect(calls, 2);
      gate.complete();
      await tester.pumpAndSettle();
      await fixture.unmount(tester);
    },
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openVariant(WidgetTester tester) =>
    _tap(tester, find.byKey(const Key('article_variant_card_0')));
Future<void> _openMovement(WidgetTester tester) =>
    _tap(tester, find.byKey(const Key('register_inventory_movement_button')));

class _Fixture {
  _Fixture() {
    final inventoryProjection = DriftInventoryProjectionStore(
      inventoryDao: InventoryDao(db),
      unitDao: UnitDao(db),
    );
    final productProjection = DriftProductoProjectionStore(
      productoDao: ProductoDao(db),
    );
    final eventStore = DriftLocalEventStore(
      db: db,
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      eventProcessor: EventProcessor(
        handlers: {
          ...inventoryEventHandlers(InventoryEventHandler(inventoryProjection)),
          ...productoEventHandlers(
            ProductoEventHandler(
              productProjection,
              variantInventoryMemoryStore: DriftVariantInventoryMemoryStore(
                dao: VariantInventoryMemoryDao(db),
              ),
              inventoryProjectionStore: inventoryProjection,
            ),
          ),
        },
      ),
      appConfigController: AppConfigController(
        AppConfig.initial.copyWith(
          mode: AppMode.standalone,
          setupCompleted: true,
        ),
      ),
    );
    const context = LocalCommandContext(deviceId: 'device', userId: 'user');
    inventory = InventoryCommandService(
      eventStore: eventStore,
      commandContext: context,
      inventoryProjectionStore: inventoryProjection,
    );
    productCommands = ProductoCommandService(
      variantInventoryMemoryStore: DriftVariantInventoryMemoryStore(
        dao: VariantInventoryMemoryDao(db),
      ),
      variantInventoryTrackingStore: DriftVariantInventoryTrackingStore(
        inventoryDao: InventoryDao(db),
        productoDao: ProductoDao(db),
      ),
      eventStore: eventStore,
      commandContext: context,
      categoriaProjectionStore: DriftCategoriaProjectionStore(
        categoriaDao: CategoriaDao(db),
      ),
      productoProjectionStore: productProjection,
      inventoryProjectionStore: inventoryProjection,
      syncedEventHistory: DriftSyncPersistence(
        db: db,
        eventDao: EventDao(db),
        eventRefDao: EventRefDao(db),
        syncCheckpointDao: SyncCheckpointDao(db),
      ),
      unidadInventarioRepository: units,
    );
  }
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  late final units = UnidadInventarioRepositoryImpl(unitDao: UnitDao(db));
  late final resources = RecursoInventarioRepositoryImpl(
    inventoryDao: InventoryDao(db),
  );
  late final products = ProductoRepositoryImpl(productoDao: ProductoDao(db));
  late final InventoryCommandService inventory;
  late final ProductoCommandService productCommands;
  Future<String> get itemId async =>
      (await db.select(db.inventoryItems).get()).single.id;
  Future<void> createArticle({bool tracking = true}) =>
      productCommands.crearArticulo(
        CrearArticuloCommand.conVariantes(
          nombre: 'Agua',
          variantes: [
            CrearArticuloVarianteCommand(
              nombre: 'Grande',
              precioVenta: '10',
              costoEstandar: null,
              inventoryUnitId: tracking ? InventoryUnitIds.piece : null,
            ),
          ],
        ),
      );
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: CategoriaRepositoryImpl(
            categoriaDao: CategoriaDao(db),
          ),
          productoRepository: products,
          productoCommandService: productCommands,
          recursoInventarioRepository: resources,
          unidadInventarioRepository: units,
          inventoryCommandService: inventory,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }
}
