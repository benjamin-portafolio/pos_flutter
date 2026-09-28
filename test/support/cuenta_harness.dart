import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/cuenta/cuenta_command_service.dart';
import 'package:pos_flutter/application/commands/cuenta/declarar_saldo_cuenta_inicial_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/account_balance_baseline_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/saldo_cuenta_inicial_declarado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_account_balance_baseline_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/repositories/account_balance_baseline_repository_impl.dart';

/// Base en memoria con el saldo en cuenta, sin caja: el hecho nuevo no necesita
/// ninguna proyección de efectivo para existir.
class CuentaHarness {
  CuentaHarness({
    AppDatabase? database,
    AppMode mode = AppMode.serverSync,
    String device = 'bank-tablet',
    String user = 'bank-user',
  }) : db = database ?? AppDatabase.forTesting(NativeDatabase.memory()),
       config = AppConfigController(AppConfig.initial.copyWith(mode: mode)),
       context = LocalCommandContext(userId: user, deviceId: device);
  final AppDatabase db;
  final AppConfigController config;
  final LocalCommandContext context;
  late final store = DriftAccountBalanceBaselineProjectionStore(db);
  late final handler = AccountBalanceBaselineEventHandler(store);
  late final processor = EventProcessor(
    handlers: {
      SaldoCuentaInicialDeclaradoPayload.eventType: handler.apply,
    },
  );
  late final events = DriftLocalEventStore(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    eventProcessor: processor,
    appConfigController: config,
  );
  late final cuenta = CuentaCommandService(
    store: store,
    events: events,
    context: context,
    config: config,
  );
  late final persistence = DriftSyncPersistence(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    syncCheckpointDao: db.syncCheckpointDao,
  );
  late final repository = AccountBalanceBaselineRepositoryImpl(db);

  /// Cambia el ajuste sin reiniciar la app, como lo hace la UI.
  void setBankEnabled(bool value) =>
      config.update(config.config.copyWith(bankEnabled: value));

  /// Declara con una identidad nueva y devuelve el evento emitido.
  Future<String> declarar({int amountMinor = 50000}) async {
    final id = const Uuid().v4();
    return cuenta.declarar(
      DeclararSaldoCuentaInicialCommand(
        baselineId: id,
        amountMinor: amountMinor,
      ),
    );
  }

  Future<void> dispose() async {
    await db.close();
    await config.dispose();
  }
}
