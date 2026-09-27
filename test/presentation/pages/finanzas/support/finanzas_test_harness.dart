import 'package:drift/native.dart';
import 'package:pos_flutter/application/commands/finanzas/categoria_financiera_command_service.dart';
import 'package:pos_flutter/application/commands/finanzas/movimiento_financiero_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/financial_category_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/financial_entry_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_financiera_creada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_financiero_registrado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_category_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_entry_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/repositories/financial_category_repository_impl.dart';
import 'package:pos_flutter/data/repositories/financial_entry_repository_impl.dart';
import 'package:pos_flutter/domain/repositories/financial_category_repository.dart';
import 'package:pos_flutter/domain/repositories/financial_entry_repository.dart';

/// Ambiente real en memoria (Drift `NativeDatabase.memory()`) para las
/// pantallas de ingresos/gastos: repositorios y command services conectados a
/// proyecciones y al event store, con los handlers financieros y el modo de
/// aplicación. Mismo montaje que `financial_flow_test.dart`, sin fakes.
class FinanzasTestHarness {
  FinanzasTestHarness(this.db, this.config);

  final AppDatabase db;
  final AppConfigController config;

  static const LocalCommandContext context = LocalCommandContext(
    userId: 'user',
    deviceId: 'tablet',
  );

  static Future<FinanzasTestHarness> create({
    AppMode mode = AppMode.serverSync,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
    return FinanzasTestHarness(db, config);
  }

  DriftFinancialCategoryProjectionStore categoryStore() =>
      DriftFinancialCategoryProjectionStore(
        db: db,
        dao: db.financialCategoryDao,
      );

  DriftFinancialEntryProjectionStore entryStore() =>
      DriftFinancialEntryProjectionStore(db: db, dao: db.financialEntryDao);

  DriftLocalEventStore eventStore() {
    final categories = categoryStore();
    return DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      appConfigController: config,
      eventProcessor: EventProcessor(
        handlers: {
          CategoriaFinancieraCreadaPayload.eventType:
              FinancialCategoryEventHandler(categories).apply,
          MovimientoFinancieroRegistradoPayload.eventType: (e) async {
            await FinancialEntryEventHandler(entryStore(), categories).apply(e);
          },
        },
      ),
    );
  }

  CategoriaFinancieraCommandService categoryCommands() =>
      CategoriaFinancieraCommandService(
        store: categoryStore(),
        events: eventStore(),
        context: context,
      );

  MovimientoFinancieroCommandService movementCommands() =>
      MovimientoFinancieroCommandService(
        store: entryStore(),
        categories: categoryStore(),
        events: eventStore(),
        context: context,
      );

  FinancialCategoryRepository categoryRepository() =>
      FinancialCategoryRepositoryImpl(db.financialCategoryDao);

  FinancialEntryRepository entryRepository() => FinancialEntryRepositoryImpl(db);

  DriftSyncPersistence persistence() => DriftSyncPersistence(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    syncCheckpointDao: db.syncCheckpointDao,
  );

  Future<void> dispose() async {
    await db.close();
    await config.dispose();
  }
}