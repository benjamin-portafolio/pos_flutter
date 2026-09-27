import 'package:pos_flutter/application/sync/sync_preflight_service.dart';
import 'package:http/http.dart' as http;
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/pending_event_revalidator.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'cash_harness.dart';

class CashSyncHarness {
  CashSyncHarness(this.h, this.client, {this.baseUrl = 'http://test'});
  final CashHarness h;
  final http.Client client;
  final String baseUrl;
  late final categories = DriftCategoriaProjectionStore(
    categoriaDao: h.db.categoriaDao,
  );
  late final spaces = DriftEspacioProjectionStore(espacioDao: h.db.espacioDao);
  late final cleaner = SyncConflictProjectionCleaner(
    espacioProjectionStore: spaces,
    categoriaProjectionStore: categories,
    categoriaConflictProjectionRestorer: CategoriaConflictProjectionRestorer(
      categories,
    ),
    categoriaMovidaConflictProjectionRestorer:
        CategoriaMovidaConflictProjectionRestorer(categories),
  );
  late final revalidator = PendingEventRevalidator(
    syncPersistence: h.persistence,
    syncedEventHistory: h.persistence,
    espacioProjectionStore: spaces,
    categoriaProjectionStore: categories,
    financialCategoryProjectionStore: h.categories,
    cashProjectionStore: h.cashStore,
    categoriaConflictProjectionRestorer: CategoriaConflictProjectionRestorer(
      categories,
    ),
    categoriaMovidaConflictProjectionRestorer:
        CategoriaMovidaConflictProjectionRestorer(categories),
  );
  late final applier = RemoteEventApplier(
    eventStore: DriftSyncedEventStore(db: h.db),
    eventProcessor: h.processor,
    serverEchoAcknowledger: ServerEchoAcknowledger(
      categoriaProjectionStore: categories,
      financialCategoryProjectionStore: h.categories,
      financialEntryProjectionStore: h.entries,
      cashProjectionStore: h.cashStore,
    ),
  );
  late final push = SyncPushService(
    syncPersistence: h.persistence,
    endpointConfig: SyncEndpointConfig(initialBaseUrl: baseUrl),
    client: client,
    conflictProjectionCleaner: cleaner,
  );
  late final preflight = SyncPreflightService(
    syncPersistence: h.persistence,
    endpointConfig: SyncEndpointConfig(initialBaseUrl: baseUrl),
    commandContext: h.context,
    remoteEventApplier: applier,
    pendingEventRevalidator: revalidator,
    client: client,
  );
  late final pull = SyncPullService(
    syncPersistence: h.persistence,
    remoteEventApplier: applier,
    endpointConfig: SyncEndpointConfig(initialBaseUrl: baseUrl),
    commandContext: h.context,
    client: client,
  );
}
