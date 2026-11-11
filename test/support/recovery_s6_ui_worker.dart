// Invoked only by the isolated PostgreSQL S6 harness; no production data/config.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/cambiar_tarifa_venta_borrador_command.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/application/recovery/baseline_bootstrap_service.dart';
import 'package:pos_flutter/application/recovery/baseline_bootstrap_transport.dart';
import 'package:pos_flutter/application/recovery/recovery_json.dart';
import 'package:pos_flutter/application/recovery/recovery_logical_schema.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_transport.dart';
import 'package:pos_flutter/application/recovery/recovery_readiness_service.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_installation.dart';
import 'package:pos_flutter/application/sync/sync_network_gate.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/recovery_revision_schema.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_snapshot_source.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_source_binder.dart';
import 'package:pos_flutter/data/local/recovery/http_baseline_bootstrap_transport.dart';
import 'package:pos_flutter/data/local/recovery/http_recovery_destination_inspector.dart';
import 'package:pos_flutter/data/local/recovery/http_connection_attempts.dart';
import 'package:pos_flutter/data/local/recovery/http_recovery_transport.dart';
import 'package:pos_flutter/data/local/recovery/sqlite_baseline_bootstrap_installer.dart';
import 'package:pos_flutter/data/local/recovery/sqlite_recovery_snapshot.dart';
import 'package:pos_flutter/data/local/recovery/sync_installation_file_store.dart';
import 'package:pos_flutter/data/local/sync/guarded_sync_client.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import 'package:pos_flutter/presentation/app/app_restart_scope.dart';
import 'package:pos_flutter/presentation/pages/recovery/recovery_readiness_screen.dart';
import 'variant_tracking_harness.dart';

class _MeasuredTransport implements RecoveryTransport {
  _MeasuredTransport(this.inner, this.timings);
  final RecoveryTransport inner;
  final Map<String, int> timings;
  @override
  Future<Map<String, Object?>> request(
    String method,
    String path, {
    List<int>? bytes,
    Map<String, String> headers = const {},
  }) async {
    final timer = Stopwatch()..start();
    try {
      return await inner.request(method, path, bytes: bytes, headers: headers);
    } finally {
      final stage = path.endsWith('/validate')
          ? 'validation_http_ms'
          : path.endsWith('/finalize')
          ? 'publication_http_ms'
          : path.contains('/chunks/')
          ? 'chunks_http_ms'
          : 'control_http_ms';
      timings[stage] = (timings[stage] ?? 0) + timer.elapsedMilliseconds;
    }
  }

  @override
  void close() => inner.close();
}

class _InterruptedBootstrap implements BaselineBootstrapTransport {
  _InterruptedBootstrap(this.inner);
  final BaselineBootstrapTransport inner;
  bool interrupted = false;
  int acknowledgements = 0;
  final downloaded = <int>[];
  @override
  Future<List<int>> descriptor() => inner.descriptor();
  @override
  Future<List<int>> chunk(int index) async {
    downloaded.add(index);
    final bytes = await inner.chunk(index);
    if (index == 1 && !interrupted) {
      interrupted = true;
      throw const SocketException('S6 connection lost between bootstrap pages');
    }
    return bytes;
  }

  @override
  Future<Map<String, Object?>> bind(String datasetId, String digest) {
    acknowledgements++;
    return inner.bind(datasetId, digest);
  }
}

void main() {
  testWidgets(
    'S6 A screen → isolated B → empty C, offline operations and convergence',
    (tester) async {
      final inputPath = Platform.environment['POS_RECOVERY_S6_INPUT']!;
      if (!inputPath.startsWith('/tmp/pos-recovery-s4-commercial-')) {
        throw StateError('Isolated fixture input required');
      }
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Map input, original;
      late Directory root, private;
      late File source, aFile;
      late AppDatabase db;
      late String originalHash;
      final timings = <String, int>{};
      final clock = Stopwatch()..start();
      var peakRss = ProcessInfo.currentRss;
      Future<void> waitFor(bool Function() ready) async {
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 90));
          do {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            if (ProcessInfo.currentRss > peakRss) {
              peakRss = ProcessInfo.currentRss;
            }
            if (ready()) {
              return;
            }
          } while (DateTime.now().isBefore(deadline));
          throw StateError(
            'UI stage timed out: ${tester.allWidgets.whereType<Text>().map((w) => w.data).join(" | ")}',
          );
        });
      }

      Future<void> press(String label, bool Function() ready) async {
        await tester.ensureVisible(find.text(label));
        await tester.runAsync(() async {
          await tester.tap(find.text(label));
        });
        await waitFor(ready);
      }

      Future<Map> admin(String path) async {
        final response = await http.post(Uri.parse('${input['bridge']}/$path'));
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map;
      }

      await tester.runAsync(() async {
        input = jsonDecode(await File(inputPath).readAsString()) as Map;
        for (final key in ['url', 'bridge']) {
          if (Uri.parse(input[key] as String).host != '127.0.0.1') {
            throw StateError('Loopback required');
          }
        }
        original =
            jsonDecode(await File(input['prepared'] as String).readAsString())
                as Map;
        root = File(inputPath).parent;
        private = Directory('${root.path}/s6');
        await private.create();
        source = File(original['snapshot_path'] as String);
        originalHash = (await sha256.bind(source.openRead()).first).toString();
        aFile = await source.copy('${root.path}/s6-A.sqlite');
        db = AppDatabase.forTesting(NativeDatabase(aFile));
      });
      final bindingDirectory = Directory('${private.path}/binding');
      final inspector = HttpRecoveryDestinationInspector();
      final connections = HttpConnectionAttempts(
        Directory('${private.path}/connection-attempts'),
      );
      final service = RecoveryReadinessService(
        requestConnection: (destination, package, {server, generation}) =>
            connections.authorizeRecovery(
              destination,
              package,
              inspector: inspector,
              server: server,
              generation: generation,
            ),
        source: DriftRecoverySnapshotSource(db),
        privateDirectory: () async => private,
        deviceId: (original['cut'] as Map)['source']['device_id'] as String,
        appRevision: 'S6-isolated-source-copy',
        openSnapshot: SqliteRecoverySnapshot.open,
        sourceBinder: DriftRecoverySourceBinder(
          db: db,
          directory: bindingDirectory,
          mode: () => AppMode.serverSync,
        ),
        transportFactory: (journal) => _MeasuredTransport(
          HttpRecoveryTransport(
            mode: AppMode.serverSync,
            destination: Uri.parse(journal['destination'] as String),
            server: journal['server_instance_id'] as String,
            generation: journal['generation_id'] as String,
            token: journal['recovery_token'] as String,
          ),
          timings,
        ),
      );
      var restarted = false;
      final config = AppConfig.initial.copyWith(
        mode: AppMode.serverSync,
        setupCompleted: true,
      );
      await tester.pumpWidget(
        AppRestartScope(
          initialConfig: config,
          restartDependencies: (_) async {
            await db.close();
            restarted = true;
            return DependencyBootstrap(appConfig: config);
          },
          builder: (_) => MaterialApp(
            home: restarted
                ? const Scaffold(body: Text('Origen reabierto'))
                : RecoveryReadinessScreen(
                    mode: AppMode.serverSync,
                    service: service,
                    inspector: inspector,
                  ),
          ),
        ),
      );
      await waitFor(
        () => find.text('Diagnosticar origen').evaluate().isNotEmpty,
      );
      var start = clock.elapsedMilliseconds;
      await press(
        'Diagnosticar origen',
        () => find.text('Preparar paquete del corte').evaluate().isNotEmpty,
      );
      timings['capture_diagnostic_ms'] = clock.elapsedMilliseconds - start;
      start = clock.elapsedMilliseconds;
      await press(
        'Preparar paquete del corte',
        () => find.textContaining('Paquete:').evaluate().isNotEmpty,
      );
      timings['package_ms'] = clock.elapsedMilliseconds - start;
      await tester.enterText(
        find.widgetWithText(TextField, 'URL HTTPS del destino'),
        input['url'] as String,
      );
      await press(
        'Comprobar destino',
        () => find.textContaining('Aprobación pendiente').evaluate().isNotEmpty,
      );
      expect(find.text('Transferir y validar paquete'), findsNothing);
      final message = tester
          .widget<Text>(find.textContaining('Aprobación pendiente'))
          .data!;
      final requestId = RegExp(r'[0-9a-f-]{36}').firstMatch(message)!.group(0)!;
      await tester.runAsync(() => admin('approve?id=$requestId'));
      await press(
        'Comprobar destino',
        () => find.text('Transferir y validar paquete').evaluate().isNotEmpty,
      );
      start = clock.elapsedMilliseconds;
      await press(
        'Transferir y validar paquete',
        () => find.text('Estado: ready_to_commit').evaluate().isNotEmpty,
      );
      timings['transfer_and_validation_ms'] = clock.elapsedMilliseconds - start;
      final publish = find.widgetWithText(
        FilledButton,
        'Publicar recuperación',
      );
      expect(tester.widget<FilledButton>(publish).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile).first);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      start = clock.elapsedMilliseconds;
      await press(
        'Publicar recuperación',
        () => find.text('Estado: completed').evaluate().isNotEmpty,
      );
      timings['publication_ms'] = clock.elapsedMilliseconds - start;
      final check = find.byType(CheckboxListTile);
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pump();
      start = clock.elapsedMilliseconds;
      await press(
        'Vincular este origen y reabrir',
        () => find.text('Origen reabierto').evaluate().isNotEmpty,
      );
      timings['source_binding_ms'] = clock.elapsedMilliseconds - start;
      await tester.runAsync(() async {
        final saved = (await SyncInstallationFileStore(
          bindingDirectory,
        ).read())!;
        expect(saved['phase'], 'needs_pull');
        final a = VariantTrackingHarness(
          database: AppDatabase.forTesting(NativeDatabase(aFile)),
          mode: AppMode.serverSync,
          context: LocalCommandContext(
            deviceId: (saved['binding'] as Map)['device_id'] as String,
            userId: 'S6-A',
          ),
          isolatedSyncHarness: true,
        );
        final cGrant = await admin('enroll');
        final transport = HttpBaselineBootstrapTransport(
          baseUri: Uri.parse(input['url'] as String),
          serverInstanceId: input['server'] as String,
          generationId: input['generation'] as String,
          enrollmentToken: cGrant['token'] as String,
        );
        start = clock.elapsedMilliseconds;
        final interrupted = _InterruptedBootstrap(transport);
        final receipt =
            ((await service.attempt())!['progress'] as Map)['receipt'] as Map;
        Future<Map<String, Object?>> installC() =>
            BaselineBootstrapService().installEmpty(
              mode: AppMode.serverSync,
              expectedServer: input['server'] as String,
              expectedGeneration: input['generation'] as String,
              expectedDigest: receipt['bootstrap_digest'] as String,
              transport: interrupted,
              installer: SqliteBaselineBootstrapInstaller(
                Directory('${private.path}/C'),
              ),
            );
        await expectLater(installC(), throwsA(isA<SocketException>()));
        expect(interrupted.downloaded, [0, 1]);
        expect(interrupted.acknowledgements, 0);
        final cResult = await installC();
        expect(interrupted.downloaded.where((i) => i == 0).length, 1);
        expect(interrupted.downloaded.where((i) => i == 1).length, 2);
        expect(interrupted.acknowledgements, 1);
        timings['empty_C_bootstrap_ms'] = clock.elapsedMilliseconds - start;
        transport.close();
        final cBinding = cResult['binding'] as Map;
        final c = VariantTrackingHarness(
          database: AppDatabase.forTesting(
            NativeDatabase(File(cResult['database_path'] as String)),
          ),
          mode: AppMode.serverSync,
          context: LocalCommandContext(
            deviceId: cBinding['device_id'] as String,
            userId: 'S6-C',
          ),
          isolatedSyncHarness: true,
        );
        final aIdentity = SyncInstallation(
          saved,
          persist: SyncInstallationFileStore(bindingDirectory).write,
        );
        final cIdentity = SyncInstallation({
          'phase': 'needs_pull',
          'endpoint': input['url'],
          'binding': cBinding,
        }, persist: (_) async {});
        final aGate = SyncNetworkGate(isServerSync: () => true),
            cGate = SyncNetworkGate(isServerSync: () => true);
        final aClient = GuardedSyncClient(
          aGate,
          http.Client(),
          installation: aIdentity,
        );
        final cClient = GuardedSyncClient(
          cGate,
          http.Client(),
          installation: cIdentity,
        );
        Future<void> pull(
          VariantTrackingHarness h,
          GuardedSyncClient client,
        ) async {
          await SyncPullService(
            syncPersistence: h.history,
            remoteEventApplier: h.remote,
            endpointConfig: SyncEndpointConfig(
              initialBaseUrl: input['url'] as String,
            ),
            commandContext: h.context,
            client: client,
          ).pullAvailableEvents();
        }

        Future<List<String>> rows(AppDatabase database, String table) async =>
            (await database.customSelect('SELECT * FROM "$table"').get())
                .map((r) => recoveryCanonical(r.data))
                .toList()
              ..sort();
        try {
          expect(a.context.deviceId, isNot(c.context.deviceId));
          expect(
            a.context.deviceId,
            isNot((original['cut'] as Map)['source']['device_id']),
          );
          final cutSnapshot = await SqliteRecoverySnapshot.open(
            File(((await service.prepared())!)['snapshot_path'] as String),
          );
          final cSnapshot = await DriftRecoverySnapshotSource(c.db).capture(
            privateDirectory: Directory('${private.path}/compare-C'),
            mode: AppMode.serverSync,
            deviceId: c.context.deviceId,
            appRevision: 'S6-C-comparison',
            cancellation: RecoveryCancellation(),
          );
          final comparisonCounts = <String, int>{};
          try {
            for (final entity in RecoveryLogicalSchema.keys.keys.where(
              (e) => ![
                'event_refs',
                'event_provenance',
                'projection_provenance',
              ].contains(e),
            )) {
              final expected =
                  cutSnapshot.exportRows(entity).map(recoveryCanonical).toList()
                    ..sort();
              final actual =
                  cSnapshot.exportRows(entity).map(recoveryCanonical).toList()
                    ..sort();
              expect(
                actual,
                expected,
                reason: 'Original A cut -> empty C logical $entity',
              );
              comparisonCounts[entity] = expected.length;
            }
          } finally {
            cutSnapshot.close();
            cSnapshot.close();
          }
          final counts = <String, int>{};
          final baselineRows = <String, List<String>>{};
          for (final table in recoveryRevisionTables.where(
            (t) => t != 'sync_checkpoints',
          )) {
            final expected = await rows(a.db, table);
            expect(
              await rows(c.db, table),
              expected,
              reason: 'A/C exact baseline $table',
            );
            counts[table] = expected.length;
            baselineRows[table] = expected;
          }
          await pull(a, aClient);
          await aIdentity.activate();
          await pull(c, cClient);
          await cIdentity.activate();
          final item = (await a.db.select(a.db.inventoryItems).get())
              .firstWhere((i) => i.active);
          final cItem = (await c.db.select(c.db.inventoryItems).get())
              .firstWhere((i) => i.active && i.id != item.id);
          final cBefore = (await c.db.select(c.db.inventoryBalances).get())
              .firstWhere((b) => b.inventoryItemId == cItem.id)
              .quantityOnHandAtomic;
          final before = (await a.db.select(a.db.inventoryBalances).get())
              .firstWhere((b) => b.inventoryItemId == item.id)
              .quantityOnHandAtomic;
          // Disconnection is an explicit closed admission gate; commands remain local.
          await aGate.pause();
          await cGate.pause();
          await a.inventoryCommands.registrarMovimiento(
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: item.id,
              movementType: TipoMovimientoInventario.stockReceipt,
              quantityDeltaAtomic: 2,
            ),
          );
          await c.inventoryCommands.registrarMovimiento(
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: cItem.id,
              movementType: TipoMovimientoInventario.stockReceipt,
              quantityDeltaAtomic: 3,
            ),
          );
          expect(await a.history.pendingEvents(), hasLength(1));
          expect(await c.history.pendingEvents(), hasLength(1));
          expect(aGate.allowsNetwork, false);
          expect(cGate.allowsNetwork, false);
          aGate.resume();
          cGate.resume();
          expect(
            (await a
                    .push(input['url'] as String, client: aClient)
                    .pushPendingEvents())
                .synced,
            1,
          );
          await pull(a, aClient);
          await pull(c, cClient);
          expect(
            (await c
                    .push(input['url'] as String, client: cClient)
                    .pushPendingEvents())
                .synced,
            1,
          );
          await pull(a, aClient);
          await pull(c, cClient);
          await pull(a, aClient);
          await pull(c, cClient);
          expect(
            (await a
                    .push(input['url'] as String, client: aClient)
                    .pushPendingEvents())
                .synced,
            0,
          );
          expect(
            (await c
                    .push(input['url'] as String, client: cClient)
                    .pushPendingEvents())
                .synced,
            0,
          );
          expect(await a.history.pendingEvents(), isEmpty);
          expect(await c.history.pendingEvents(), isEmpty);
          for (final h in [a, c]) {
            expect(
              (await h.db.select(h.db.inventoryBalances).get())
                  .firstWhere((b) => b.inventoryItemId == item.id)
                  .quantityOnHandAtomic,
              before + 2,
            );
            expect(
              (await h.db.select(h.db.inventoryBalances).get())
                  .firstWhere((b) => b.inventoryItemId == cItem.id)
                  .quantityOnHandAtomic,
              cBefore + 3,
            );
            for (final table in [
              'sales',
              'sale_payments',
              'customer_payments',
              'credit_sales',
              'credit_allocations',
              'cash_movements',
              'cash_sessions',
              'sale_adjustments',
            ]) {
              expect(
                await rows(h.db, table),
                baselineRows[table],
                reason: 'No new financial effect $table',
              );
            }
          }
          for (final table in [
            'inventory_balances',
            'inventory_movements',
            'sales',
            'sale_payments',
            'customer_payments',
            'credit_allocations',
            'cash_movements',
            'sale_reconciliation_effects',
          ]) {
            expect(
              await rows(a.db, table),
              await rows(c.db, table),
              reason: 'convergence $table',
            );
          }
          expect(
            (await sha256.bind(source.openRead()).first).toString(),
            originalHash,
          );
          final recipeVariant =
              (await c.db.select(c.db.recipeComponents).get()).first.variantId;
          final offerVariant = (await c.db.select(c.db.productVariants).get())
              .firstWhere((v) => v.active && v.offerPriceMinor != null);
          Future<String> sell(
            String variant,
            int expected, {
            bool offer = false,
          }) async {
            await c.drafts.agregar(
              AgregarProductoBorradorCommand(variantId: variant),
            );
            var draft = (await c.db.saleDao.findDraft(
              c.context.userId,
              c.context.deviceId,
            ))!;
            if (offer) {
              await c.drafts.cambiarTarifa(
                CambiarTarifaVentaBorradorCommand(
                  operationId: const Uuid().v4(),
                  saleId: draft.id,
                  pricingMode: 'offer',
                  expectedVersion: draft.version,
                  expectedDraftEventId: draft.lastEventId,
                  expectedTotalMinor: draft.totalMinor,
                ),
              );
              draft = (await c.db.saleDao.findDraft(
                c.context.userId,
                c.context.deviceId,
              ))!;
            }
            expect(draft.totalMinor, expected);
            return c.sales.confirmar(
              ConfirmarVentaCommand(
                saleId: draft.id,
                expectedDraftEventId: draft.lastEventId!,
                expectedTotalMinor: draft.totalMinor,
                paymentMethod: 'transfer',
              ),
            );
          }

          final recipeEvent = await sell(recipeVariant, 300);
          final offerEvent = await sell(
            offerVariant.id,
            offerVariant.offerPriceMinor!,
            offer: true,
          );
          expect(
            (await c
                    .push(input['url'] as String, client: cClient)
                    .pushPendingEvents())
                .synced,
            2,
          );
          await pull(a, aClient);
          await pull(c, cClient);
          final financialAfter = <String, List<String>>{};
          for (final table in [
            'sales',
            'sale_payments',
            'inventory_movements',
            'inventory_balances',
            'cash_movements',
            'credit_allocations',
          ]) {
            final expected = await rows(a.db, table);
            expect(
              await rows(c.db, table),
              expected,
              reason: 'recipe/offer convergence $table',
            );
            financialAfter[table] = expected;
          }
          expect(
            (await a.db.select(a.db.sales).get()).length,
            counts['sales']! + 2,
          );
          expect(
            (await a.db.select(a.db.salePayments).get()).length,
            counts['sale_payments']! + 2,
          );
          for (final entry in {recipeEvent: -2, offerEvent: -1}.entries) {
            final movements = (await a.db.select(a.db.inventoryMovements).get())
                .where((m) => m.eventId == entry.key)
                .toList();
            expect(movements, hasLength(1));
            expect(movements.single.quantityDeltaAtomic, entry.value);
          }
          await pull(a, aClient);
          await pull(c, cClient);
          expect(
            (await c
                    .push(input['url'] as String, client: cClient)
                    .pushPendingEvents())
                .synced,
            0,
          );
          for (final entry in financialAfter.entries) {
            expect(await rows(a.db, entry.key), entry.value);
            expect(await rows(c.db, entry.key), entry.value);
          }
          final prepared = (await service.prepared())!;
          final manifest =
              jsonDecode(
                    await File(
                      '${prepared['package_path']}/manifest.json',
                    ).readAsString(),
                  )
                  as Map;
          await File('${root.path}/s6-report.json').writeAsString(
            jsonEncode({
              'result': 'passed',
              'dataset_id': cBinding['dataset_id'],
              'source_device': (original['cut'] as Map)['source']['device_id'],
              'A_device': a.context.deviceId,
              'C_device': c.context.deviceId,
              'baseline_counts': counts,
              'original_cut_to_C_logical_counts': comparisonCounts,
              'logical_comparison_exceptions': [
                'event_refs reconstructed canonically by receiver; checked by validators',
                'event_provenance original SQLite insertion order differs after bootstrap',
                'projection_provenance records normalization of physical losing effects',
              ],
              'baseline_comparison':
                  'All columns and rows of recoveryRevisionTables except sync_checkpoints, A after binding vs empty C; checkpoint identity/H validated by installer',
              'source_snapshot_preserved': true,
              'package_bytes': (manifest['chunks'] as List).fold<int>(
                0,
                (n, ch) => n + ch['bytes'] as int,
              ),
              'manifest_bytes': await File(
                '${prepared['package_path']}/manifest.json',
              ).length(),
              'chunks': (manifest['chunks'] as List).length,
              'timings': timings,
              'rss_sampled_peak': peakRss,
              'rss_scope':
                  'Flutter widget test VM; sampled between UI polls, not a maximum or mobile measurement',
              'stock_before': before,
              'stock_after': before + 2,
              'C_stock_before': cBefore,
              'C_stock_after': cBefore + 3,
              'offline_pending_per_device': 1,
              'money_tables_unchanged_during_inventory_phase': true,
              'new_recipe_sale_total_minor': 300,
              'new_offer_sale_total_minor': offerVariant.offerPriceMinor,
              'new_recipe_consumption': -2,
              'new_offer_consumption': -1,
              'new_sales_idempotent': true,
              'C_lost_page_resumed_same_dataset': true,
            }),
          );
        } finally {
          aClient.close();
          cClient.close();
          await a.db.close();
          await c.db.close();
        }
      });
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
