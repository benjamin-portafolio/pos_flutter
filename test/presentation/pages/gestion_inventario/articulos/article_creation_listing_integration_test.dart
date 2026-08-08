import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/producto_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/projections/categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/inventory_article_card.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';

void main() {
  testWidgets('un alta local aparece automáticamente en el listado', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final productoDao = ProductoDao(db);
    final projectionStore = DriftProductoProjectionStore(
      productoDao: productoDao,
    );
    final eventStore = DriftLocalEventStore(
      db: db,
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      eventProcessor: EventProcessor(
        handlers: productoEventHandlers(ProductoEventHandler(projectionStore)),
      ),
      appConfigController: AppConfigController(
        AppConfig.initial.copyWith(
          mode: AppMode.standalone,
          setupCompleted: true,
        ),
      ),
    );
    final commandService = ProductoCommandService(
      eventStore: eventStore,
      commandContext: const LocalCommandContext(
        deviceId: 'test-device',
        userId: 'test-user',
      ),
      categoriaProjectionStore: _EmptyCategoriaProjectionStore(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: CategoriaRepositoryImpl(
            categoriaDao: CategoriaDao(db),
          ),
          productoRepository: ProductoRepositoryImpl(productoDao: productoDao),
          productoCommandService: commandService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No hay artículos.'), findsOneWidget);

    await tester.tap(find.byTooltip('Agregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_article_option')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('article_name_field')),
      'Chocolate caliente',
    );
    await tester.enterText(
      find.byKey(const Key('article_price_field')),
      '58.00',
    );
    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();

    expect(find.text('Artículo guardado.'), findsOneWidget);
    expect(find.text('Chocolate caliente'), findsOneWidget);
    expect(find.text(r'$58.00'), findsOneWidget);
    expect(find.byType(InventoryArticleCard), findsOneWidget);
    expect(await db.select(db.products).get(), hasLength(1));
    expect(await db.select(db.productVariants).get(), hasLength(1));
    expect(await db.select(db.eventRefs).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

class _EmptyCategoriaProjectionStore implements CategoriaProjectionStore {
  @override
  Future<CategoriaProjection?> findById(String id) async => null;

  @override
  Future<List<CategoriaProjection>> findAllOrdered() async => const [];

  @override
  Future<void> advanceLastServerSequence(String id, int serverSequence) async {}

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> deleteCreatedByEvent(String eventId) async {}

  @override
  Future<void> insert(CategoriaProjection projection) async {}

  @override
  Future<void> update(CategoriaProjection projection) async {}

  @override
  Future<void> updateSyncMetadata(
    String id, {
    required String eventId,
    int? serverSequence,
  }) async {}
}
