import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/handlers/cash_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/venta_confirmada_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_cash_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/repositories/cash_repository_impl.dart';
import 'package:pos_flutter/data/repositories/customer_account_repository_impl.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_status.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/caja/models/sale_receipt_display.dart';

import '../../../support/quotation_harness.dart';

/// Cierre: saldos de negocio no vacíos, inventario medido y restore de historia.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const measuredResource = '00000000-0000-4000-8000-000000000081';
  const captureTables = {
    'quotations',
    'quotation_items',
    'sales',
    'sale_items',
    'events',
    'event_refs',
  };

  Future<void> export(String name, Object value) async {
    final output = Platform.environment['POS_QUOTATION_VERIFICATION_DIR'];
    if (output == null) return;
    await Directory(output).create(recursive: true);
    await File(
      '$output/$name.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(value));
  }

  Future<void> addAll(QuotationHarness h) async {
    await h.add();
    await h.add(QuotationHarness.recipeId);
    await h.add(QuotationHarness.measuredId);
  }

  Future<Map<String, String>> businessBalances(
    QuotationHarness h,
    String customer,
  ) async {
    final account = await CustomerAccountRepositoryImpl(
      h.db,
    ).watchAccount(customer).first;
    final cash = (await CashRepositoryImpl(h.db).watchSessions().first).single;
    return {
      'account_balance_minor': account.balanceMinor.toString(),
      'cash_expected_minor': cash.expectedMinor.toString(),
    };
  }

  for (final mode in AppMode.values) {
    for (final method in ['cash', 'transfer', 'credit']) {
      test(
        'P10/P18/P23/P24/P25: recuperación vigente, saldos y recibo $mode/$method',
        () async {
          final h = QuotationHarness(mode: mode);
          try {
            await h.seed();
            await h.db
                .into(h.db.inventoryItems)
                .insert(
                  InventoryItemsCompanion.insert(
                    id: measuredResource,
                    name: 'Café con existencias por peso',
                    defaultUnitId: InventoryUnitIds.kilogram,
                    createdEventId: const Value(
                      QuotationHarness.resourceEventId,
                    ),
                    lastEventId: const Value(QuotationHarness.resourceEventId),
                  ),
                );
            await h.db
                .into(h.db.inventoryBalances)
                .insert(
                  InventoryBalancesCompanion.insert(
                    inventoryItemId: measuredResource,
                    quantityOnHandAtomic: 5000,
                    quantityAvailableAtomic: 5000,
                    lastEventId: QuotationHarness.resourceEventId,
                  ),
                );
            await (h.db.update(
              h.db.productVariants,
            )..where((t) => t.id.equals(QuotationHarness.measuredId))).write(
              const ProductVariantsCompanion(
                inventoryItemId: Value(measuredResource),
              ),
            );
            h.config.update(h.config.config.copyWith(cashEnabled: true));
            await h.cash.abrir(
              const AbrirCajaCommand(
                sessionId: '00000000-0000-4000-8000-000000000082',
                openingMinor: 20000,
              ),
            );
            final customer = await h.customer();
            // Deuda, pagos, caja y consumo previos: detectar también mutaciones de saldos.
            for (final priorMethod in ['credit', 'cash', 'transfer']) {
              await addAll(h);
              await h.confirm(method: priorMethod, clienteId: customer);
            }
            expect(await h.db.select(h.db.creditSales).get(), hasLength(1));
            expect(await h.db.select(h.db.salePayments).get(), hasLength(2));
            final baseline = await h.contents(excluded: captureTables);
            final initialBalances = await businessBalances(h, customer);
            expect(initialBalances, {
              'account_balance_minor': '-13401',
              'cash_expected_minor': '33401',
            });
            await addAll(h);
            expect(await h.contents(excluded: captureTables), baseline);
            final save = await h.intent();
            await h.service().guardar(save);
            expect(await h.contents(excluded: captureTables), baseline);
            await h.drafts.limpiar(
              LimpiarVentaBorradorCommand(
                saleId: save.saleId,
                expectedDraftEventId: save.expectedDraftEventId,
              ),
            );
            expect(await h.contents(excluded: captureTables), baseline);
            // El precio al guardar no se congela: recuperar usa el catálogo nuevo.
            await (h.db.update(
              h.db.productVariants,
            )..where((t) => t.id.equals(QuotationHarness.directId))).write(
              const ProductVariantsCompanion(
                salePriceMinor: Value(12000),
                standardCostMinor: Value(1300),
              ),
            );
            await (h.db.update(
              h.db.productVariants,
            )..where((t) => t.id.equals(QuotationHarness.measuredId))).write(
              const ProductVariantsCompanion(
                salePriceMinor: Value(20001),
                standardCostMinor: Value(1700),
              ),
            );
            final currentBaseline = await h.contents(excluded: captureTables);
            final recovery = RecuperarCotizacionCommand(
              quotationId: save.quotationId,
              expectedQuotationEventId: save.eventId,
            );
            await h.service().recuperar(recovery);
            final afterRecovery = await h.contents(excluded: captureTables);
            expect(afterRecovery, currentBaseline);
            expect(await businessBalances(h, customer), initialBalances);
            final recovered = await h.db.saleDao.items(recovery.saleId);
            expect(recovered.map((l) => l.snapshot.unitPriceMinor), [
              12000,
              2400,
              20001,
            ]);
            expect(recovered.map((l) => l.snapshot.standardCostMinor), [
              1300,
              900,
              1700,
            ]);
            expect(
              (await h.db.saleDao.findById(recovery.saleId))!.totalMinor,
              29401,
            );
            // Confirmar y el recibo mantienen la captura aunque cambie otra vez.
            await (h.db.update(
              h.db.productVariants,
            )..where((t) => t.id.equals(QuotationHarness.directId))).write(
              const ProductVariantsCompanion(salePriceMinor: Value(13000)),
            );
            final beforeCharge = await h.contents();
            final confirmation = await h.confirm(
              method: method,
              clienteId: customer,
            );
            final afterCharge = await h.contents();
            final chargedBalances = await businessBalances(h, customer);
            expect(chargedBalances, {
              'account_balance_minor': method == 'credit' ? '-42802' : '-13401',
              'cash_expected_minor': method == 'cash' ? '62802' : '33401',
            });
            final movements = await (h.db.select(
              h.db.inventoryMovements,
            )..where((t) => t.eventId.equals(confirmation))).get();
            expect(
              movements.map((m) => m.quantityDeltaAtomic).toList()..sort(),
              [-750, -3, -1],
            );
            final balances = await h.db.select(h.db.inventoryBalances).get();
            expect(
              balances
                  .singleWhere((b) => b.inventoryItemId == measuredResource)
                  .quantityOnHandAtomic,
              2000,
            );
            expect(
              balances
                  .singleWhere(
                    (b) => b.inventoryItemId == QuotationHarness.resourceId,
                  )
                  .quantityOnHandAtomic,
              984,
            );
            expect(
              balances.every(
                (b) => b.quantityOnHandAtomic == b.quantityAvailableAtomic,
              ),
              isTrue,
            );
            expect(
              (afterCharge['sale_payments'] as List).length,
              2 + (method == 'credit' ? 0 : 1),
            );
            expect(
              (afterCharge['credit_sales'] as List).length,
              1 + (method == 'credit' ? 1 : 0),
            );
            final cashBefore = (baseline['cash_movements'] as List).length;
            expect(
              (afterCharge['cash_movements'] as List).length,
              cashBefore + (method == 'cash' ? 1 : 0),
            );
            expect(
              (await h.repository.estimate(
                (await h.repository.findById(save.quotationId))!,
              )).totalMinor,
              30401,
            );
            expect(
              (await h.repository.findById(save.quotationId))!.status,
              QuotationStatus.vendida,
            );
            // Un intento duplicado y replay no producen un segundo cobro/consumo.
            await expectLater(
              h.confirm(
                method: method,
                clienteId: customer,
                saleId: recovery.saleId,
              ),
              throwsStateError,
            );
            final confirmedEvent = (await h.db.quotationDao.findEventById(
              confirmation,
            ))!;
            final payload = VentaConfirmadaPayload.fromJson(
              confirmedEvent.payload,
            );
            expect(payload.totalMinor, 29401);
            expect(payload.lines.map((l) => l.snapshot.unitPriceMinor), [
              12000,
              2400,
              20001,
            ]);
            expect(payload.dependencyEventIds, isNot(contains(save.eventId)));
            expect(
              payload.dependencyEventIds,
              isNot(contains(recovery.eventId)),
            );
            expect(
              payload
                  .refs(recovery.saleId)
                  .where((r) => r.refType.startsWith('quotation')),
              isEmpty,
            );
            final pending = await h.db.eventDao.obtenerEventosPendientes();
            expect(
              pending.any((e) => e.eventId == confirmation),
              mode == AppMode.serverSync,
            );
            expect(
              pending.where(
                (e) =>
                    e.aggregateType == 'quotation' ||
                    e.aggregateType == 'sale_draft',
              ),
              isEmpty,
            );
            final receipt = (await ConfirmedSaleRepositoryImpl(
              DriftConfirmedSaleStore(h.db),
            ).watchSales().first).singleWhere((s) => s.id == recovery.saleId);
            final display = SaleReceiptDisplay(receipt);
            expect(receipt.totalMinor, 29401);
            expect(receipt.items.map((l) => l.unitPriceMinor), [
              12000,
              2400,
              20001,
            ]);
            expect(display.totals, contains(('Total general', r'$294.01')));
            expect(
              display.paymentLabel,
              {
                'cash': 'Efectivo',
                'transfer': 'Transferencia',
                'credit': 'Crédito',
              }[method],
            );
            expect(
              receipt.paymentReference,
              method == 'transfer' ? 'SPEI-123' : null,
            );
            expect(receipt.clienteId, customer);
            await VentaConfirmadaEventHandler(
              DriftConfirmedSaleStore(h.db),
              cash: CashEventHandler(DriftCashProjectionStore(h.db)),
            ).apply(confirmedEvent);
            expect(await h.contents(), afterCharge);
            expect(await businessBalances(h, customer), chargedBalances);
            await export('saldos-${mode.name}-$method', {
              'baseline_business': currentBaseline,
              'after_recovery_business': afterRecovery,
              'before_charge': beforeCharge,
              'after_charge': afterCharge,
              'initial_balances': initialBalances,
              'after_charge_balances': chargedBalances,
              'unchanged_until_charge': true,
              'effects_once': true,
              'captured_total_minor': receipt.totalMinor,
              'current_estimate_minor': 30401,
              'receipt': display.semanticLabel,
              'pending_confirmation': mode == AppMode.serverSync,
              'no_remote_quotation_dependency': true,
            });
          } finally {
            await h.dispose();
          }
        },
      );
    }

    for (final sold in [false, true]) {
      test(
        'C22/C27/C28/C34: restore de recuperación con historia $mode/sold=$sold',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'pos_quotation_closure_',
          );
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path,
          );
          var h = QuotationHarness(database: AppDatabase(), mode: mode);
          try {
            await h.seed();
            await addAll(h);
            final save = await h.intent();
            await h.service().guardar(save);
            await h.drafts.limpiar(
              LimpiarVentaBorradorCommand(saleId: save.saleId),
            );
            final first = RecuperarCotizacionCommand(
              quotationId: save.quotationId,
              expectedQuotationEventId: save.eventId,
            );
            await h.service().recuperar(first);
            final historical = (await h.db.quotationDao.findEventById(
              first.eventId,
            ))!;
            await h.drafts.limpiar(
              LimpiarVentaBorradorCommand(saleId: first.saleId),
            );
            final current = RecuperarCotizacionCommand(
              quotationId: save.quotationId,
              expectedQuotationEventId: first.eventId,
            );
            await h.service().recuperar(current);
            final line = (await h.db.saleDao.items(current.saleId)).first;
            await h.drafts.actualizarProducto(
              ActualizarProductoBorradorCommand(
                saleItemId: line.id,
                quantity: 4,
              ),
            );
            if (sold) {
              final id = await h.confirm();
              if (mode == AppMode.serverSync) {
                await h.db.eventDao.actualizarEstadoSincronizacion(
                  id,
                  'conflict',
                );
              }
            }
            await h.db.customStatement(
              'CREATE TABLE closure_marker(value TEXT)',
            );
            await h.db.customStatement(
              "INSERT INTO closure_marker VALUES ('keep after restore and second startup')",
            );
            final before = await h.contents();
            final snapshot = await DriftDatabaseSnapshotService(
              db: h.db,
              stateReader: DriftDatabaseStateReader(db: h.db),
            ).createSnapshot();
            try {
              if (!sold) {
                await h.drafts.limpiar(
                  LimpiarVentaBorradorCommand(saleId: current.saleId),
                );
              }
              await h.db.customStatement('DELETE FROM closure_marker');
              await DriftDatabaseRestoreService(
                db: h.db,
              ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
              h.config.dispose();
              h = QuotationHarness(database: AppDatabase(), mode: mode);
              expect(await h.contents(), before);
              final q = (await h.repository.findById(save.quotationId))!;
              expect(q.currentSaleId, current.saleId);
              expect(
                q.status,
                sold ? QuotationStatus.vendida : QuotationStatus.enVenta,
              );
              expect(
                (await h.db.saleDao.items(
                  current.saleId,
                )).first.snapshot.quantity,
                4,
              );
              expect(q.items.first.quantity, 1);
              await h.recoveryHandler.apply(historical);
              await h.handler.apply(
                (await h.db.quotationDao.findEventById(save.eventId))!,
              );
              expect(await h.db.saleDao.findById(first.saleId), isNull);
              if (sold) {
                await expectLater(
                  h.service().recuperar(current),
                  throwsStateError,
                );
              } else {
                final continued = await h.service().recuperar(current);
                expect(continued.saleId, current.saleId);
                expect(continued.draftAvailable, isTrue);
              }
              expect(await h.contents(), before);
              await h.dispose();
              h = QuotationHarness(database: AppDatabase(), mode: mode);
              expect(await h.contents(), before);
              expect(
                (await h.db
                        .customSelect('SELECT value FROM closure_marker')
                        .get())
                    .single
                    .data['value'],
                'keep after restore and second startup',
              );
              expect(
                (await h.db.customSelect('PRAGMA integrity_check').get())
                    .single
                    .data
                    .values
                    .single,
                'ok',
              );
              expect(
                await h.db.customSelect('PRAGMA foreign_key_check').get(),
                isEmpty,
              );
              final output =
                  Platform.environment['POS_QUOTATION_VERIFICATION_DIR'];
              final name =
                  'restore-${mode.name}-${sold ? 'vendida' : 'en-venta'}';
              if (output != null) {
                await Directory(output).create(recursive: true);
                await snapshot.file.copy('$output/$name.sqlite');
              }
              await export(name, {
                'sha256': snapshot.sha256,
                'restored_contents': before,
                'second_startup_preserved': true,
                'integrity_check': 'ok',
                'foreign_key_check': [],
                'historical_replay_preserved': true,
              });
            } finally {
              await snapshot.file.parent.delete(recursive: true);
            }
          } finally {
            await h.dispose();
            messenger.setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
            await temp.delete(recursive: true);
          }
        },
      );
    }
  }
}
