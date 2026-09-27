import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/application/commands/caja/caja_command_service.dart';
import 'package:pos_flutter/application/commands/finanzas/categoria_financiera_command_service.dart';
import 'package:pos_flutter/application/commands/finanzas/crear_categoria_financiera_command.dart';
import 'package:pos_flutter/application/commands/finanzas/movimiento_financiero_command_service.dart';
import 'package:pos_flutter/application/commands/finanzas/registrar_movimiento_financiero_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/cash_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/financial_category_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/financial_entry_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/caja_abierta_payload.dart';
import 'package:pos_flutter/application/sync/payloads/caja_cerrada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_financiera_creada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_financiero_registrado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_cash_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_category_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_entry_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';

class CashHarness {
  CashHarness({
    AppDatabase? database,
    AppMode mode = AppMode.serverSync,
    String device = 'cash-tablet',
  }) : db = database ?? AppDatabase.forTesting(NativeDatabase.memory()),
       config = AppConfigController(AppConfig.initial.copyWith(mode: mode)),
       context = LocalCommandContext(userId: 'cash-user', deviceId: device);
  final AppDatabase db;
  final AppConfigController config;
  final LocalCommandContext context;
  late final cashStore = DriftCashProjectionStore(db);
  late final categories = DriftFinancialCategoryProjectionStore(
    db: db,
    dao: db.financialCategoryDao,
  );
  late final entries = DriftFinancialEntryProjectionStore(
    db: db,
    dao: db.financialEntryDao,
  );
  late final cashHandler = CashEventHandler(cashStore);
  late final processor = EventProcessor(
    handlers: {
      CajaAbiertaPayload.eventType: cashHandler.apply,
      CajaCerradaPayload.eventType: cashHandler.apply,
      CategoriaFinancieraCreadaPayload.eventType: FinancialCategoryEventHandler(
        categories,
      ).apply,
      MovimientoFinancieroRegistradoPayload.eventType:
          FinancialEntryEventHandler(
            entries,
            categories,
            cash: cashHandler,
          ).apply,
    },
  );
  late final events = DriftLocalEventStore(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    eventProcessor: processor,
    appConfigController: config,
  );
  late final cash = CajaCommandService(
    store: cashStore,
    events: events,
    context: context,
    config: config,
  );
  late final finance = MovimientoFinancieroCommandService(
    store: entries,
    categories: categories,
    events: events,
    context: context,
    cash: cash,
  );
  late final persistence = DriftSyncPersistence(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    syncCheckpointDao: db.syncCheckpointDao,
  );

  /// Cambia el ajuste de captura sin reiniciar la app, como lo hace la UI.
  void setCashEnabled(bool value) =>
      config.update(config.config.copyWith(cashEnabled: value));

  Future<String> open({int amount = 10000}) async {
    final id = const Uuid().v4();
    await cash.abrir(AbrirCajaCommand(sessionId: id, openingMinor: amount));
    return id;
  }

  Future<RegistrarMovimientoFinancieroCommand> command({
    String direction = 'in',
    String method = 'cash',
    bool drawer = true,
    int amount = 2500,
  }) async {
    final id = const Uuid().v4();
    await CategoriaFinancieraCommandService(
      store: categories,
      events: events,
      context: context,
    ).crear(
      CrearCategoriaFinancieraCommand(
        categoryId: id,
        name: 'Varios',
        direction: direction == 'in'
            ? FinancialDirection.income
            : FinancialDirection.expense,
        nature: FinancialNature.operating,
      ),
    );
    return RegistrarMovimientoFinancieroCommand(
      entryId: const Uuid().v4(),
      categoryId: id,
      amountMinor: amount,
      method: method,
      occurredAtMs: DateTime.now().millisecondsSinceEpoch,
      affectsDrawer: drawer,
    );
  }

  Future<String> entry({
    String direction = 'in',
    String method = 'cash',
    bool drawer = true,
    int amount = 2500,
  }) async => finance.registrar(
    await command(
      direction: direction,
      method: method,
      drawer: drawer,
      amount: amount,
    ),
  );
  Future<void> dispose() async {
    await db.close();
    await config.dispose();
  }
}
