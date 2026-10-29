import 'package:pos_flutter/presentation/pages/informes/models/sales_reports_calculator.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pos_flutter/application/sync/sync_conflict_report_service.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/prepare_sale_adjustment.dart';
import 'package:pos_flutter/application/commands/ventas/registrar_devolucion_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/devolucion_venta_registrada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/operacion_venta_conciliada_payload.dart';
import 'package:pos_flutter/application/sync/projections/cash_projection_store.dart';
import 'package:pos_flutter/application/sync/sale_adjustment_availability.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_health_service.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/local/sync/sync_capability_file_store.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_adjustment_repository_impl.dart';
import 'package:pos_flutter/domain/repositories/sale_adjustment_repository.dart';
import 'package:pos_flutter/presentation/pages/ajustes/sale_adjustment_receipt_screen.dart';
import 'package:pos_flutter/presentation/pages/ajustes/sale_incident_screen.dart';
import 'package:pos_flutter/presentation/pages/hoy/today_sales_screen.dart';
import 'variant_tracking_harness.dart';

/// Public commands and handlers: no isolatedSyncHarness bypass. Real HTTP,
/// independent SQLite files, and installation capability files under temp only.
Future<void> verifyPublicHttpUi(
  WidgetTester tester,
  String url,
  Directory dir,
) async {
  final font = Platform.environment['POS_SESSION4_FONT'];
  final icons = Platform.environment['POS_SESSION4_ICONS'];
  for (final entry in {
    'TabletQA': font,
    'Roboto': font,
    'MaterialIcons': icons,
  }.entries) {
    if (entry.value != null) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(await File(entry.value!).readAsBytes()),
            ),
          ))
          .load();
    }
  }
  final boundary = GlobalKey();
  Widget surface(Widget child) => RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      theme: ThemeData(fontFamily: 'TabletQA'),
      home: child,
    ),
  );
  Future<void> capture(String name) async {
    final directory = Platform.environment['POS_SESSION4_VISUAL_DIR'];
    if (directory == null) return;
    await tester.pumpAndSettle();
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/$name-1280x900.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  const uuid = Uuid();
  final link = _SwitchableLink();
  final clients = <VariantTrackingHarness>[];
  VariantTrackingHarness terminal(String letter) {
    final h = VariantTrackingHarness(
      mode: AppMode.serverSync,
      database: AppDatabase.forTesting(
        NativeDatabase(File('${dir.path}/public-$letter.sqlite')),
      ),
      context: LocalCommandContext(deviceId: uuid.v4(), userId: 'session5'),
      availabilityFactory: (config) {
        final endpoint = SyncEndpointConfig(initialBaseUrl: url);
        final store = SyncCapabilityFileStore(
          directoryProvider: () async =>
              Directory('${dir.path}/capabilities-$letter'),
        );
        return SaleAdjustmentAvailability(
          config: config,
          endpoint: endpoint,
          store: store,
          health: () => SyncHealthService(
            endpointConfig: endpoint,
            client: link,
            capabilityStore: store,
          ),
        );
      },
    );
    h.config.update(h.config.config.copyWith(cashEnabled: false));
    clients.add(h);
    return h;
  }

  final e = terminal('E'), f = terminal('F');
  Future<void> pushAll(VariantTrackingHarness h) async {
    for (
      var i = 0;
      i < 12 && (await h.history.pendingEvents()).isNotEmpty;
      i++
    ) {
      await h.push(url).pushPendingEvents();
    }
    expect(await h.history.pendingEvents(), isEmpty);
  }

  Future<void> settleIo() async {
    for (var n = 0; n < 8; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tap(String label) async {
    final finder = find.text(label);
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await settleIo();
  }

  Future<void> returnFromToday(VariantTrackingHarness h, String saleId) async {
    final repository = SaleAdjustmentRepositoryImpl(h.db);
    final sales = ConfirmedSaleRepositoryImpl(
      DriftConfirmedSaleStore(h.db),
      adjustments: repository,
    );
    getIt.registerSingleton<SaleAdjustmentRepository>(repository);
    getIt.registerSingleton<SaleAdjustmentCommandService>(h.adjustments);
    getIt.registerSingleton<CashProjectionStore>(h.cashStore);
    try {
      await tester.pumpWidget(
        surface(Scaffold(body: TodaySalesScreen(repository: sales))),
      );
      await tester.pumpAndSettle();
      await capture('server-today');
      // The server may contain documents from the preceding scenario: select the
      // menu inside this sale's row rather than relying on global text counts.
      final row = find.byKey(ValueKey('today-sale-$saleId'));
      await tester.ensureVisible(row);
      await tester.tap(
        find.descendant(of: row, matching: find.byTooltip('Acciones de venta')),
      );
      await tester.pumpAndSettle();
      await tap('Registrar devolución');
      final sale = (await repository.watchSales().first).singleWhere(
        (s) => s.original.id == saleId,
      );
      final quantity = find.byKey(
        ValueKey('return-quantity-${sale.original.items.single.id}'),
      );
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, '1');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo obligatorio'),
        'Devolución real sesión 5',
      );
      await tap('Revisar consecuencias');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: quantity,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '1',
      );
      await tap('Confirmo las consecuencias y la liquidación declarada.');
      await capture('server-return');
      await tap('Confirmar devolución');
      expect(find.byType(SaleAdjustmentReceiptScreen), findsOneWidget);
      await capture('server-adjustment-receipt');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await getIt.unregister<SaleAdjustmentRepository>();
      await getIt.unregister<SaleAdjustmentCommandService>();
      await getIt.unregister<CashProjectionStore>();
    }
  }

  Future<void> nextReturn(VariantTrackingHarness h, String saleId) async {
    final sale = (await SaleAdjustmentRepositoryImpl(
      h.db,
    ).watchSales().first).singleWhere((s) => s.original.id == saleId);
    final p = await PrepareSaleAdjustment(h.adjustments, h.cashStore)(
      saleId: saleId,
      expectedRevision: sale.revision,
      voidSale: false,
      reason: 'Otra devolución oficial',
      action: 'refund_completed',
      selections: {
        sale.original.items.single.id: (quantity: 1, destination: 'restock'),
      },
    );
    await h.adjustments.devolver(
      RegistrarDevolucionVentaCommand(
        payload: DevolucionVentaRegistradaPayload.fromJson(p.toJson()),
        userId: h.context.userId,
        deviceId: h.context.deviceId,
      ),
    );
    await pushAll(h);
  }

  try {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await expectLater(e.adjustments.ensureAvailable(), throwsStateError);
    await e.adjustments.ensureAvailable(refresh: true);
    await f.adjustments.ensureAvailable(refresh: true);
    final ids = await e.create(initial: '10');
    for (var i = 0; i < 3; i++) {
      await e.drafts.agregar(
        AgregarProductoBorradorCommand(variantId: ids.variantId),
      );
    }
    final sale = (await e.db.select(e.db.sales).get()).single;
    await e.sales.confirmar(
      ConfirmarVentaCommand(
        saleId: sale.id,
        expectedDraftEventId: sale.lastEventId!,
        expectedTotalMinor: sale.totalMinor,
        paymentMethod: 'cash',
        receivedMinor: 3000,
      ),
    );
    await pushAll(e);
    await f.pull(url).pullAvailableEvents(limit: 1);
    link.online = false;
    await returnFromToday(e, sale.id);
    await returnFromToday(f, sale.id);
    for (final h in [e, f]) {
      final pending = (await h.history.pendingEvents()).single;
      expect(pending.deliveryStatus, 'pending');
      expect(await h.history.refsForEvents([pending.eventId]), isNotEmpty);
      await expectLater(
        h.push(url, client: link).pushPendingEvents(),
        throwsA(anything),
      );
      expect((await h.history.pendingEvents()).single.eventId, pending.eventId);
    }
    link.online = true;
    await pushAll(e);
    await f.pull(url).pullAvailableEvents(limit: 1);
    await f.preflight(url).revalidatePendingEvents();
    final incident =
        (await f.db.select(f.db.saleDeliveryIncidents).get()).single;
    expect(await f.adjustmentStore.hasIncident(sale.id), true);
    await SyncConflictReportService(
      syncPersistence: f.history,
      endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
    ).reportLocalConflicts();
    await tester.pumpWidget(
      surface(
        SaleIncidentScreen(
          incidentId: incident.id,
          commands: f.reconciliations,
          adjustments: f.adjustmentStore,
          cash: f.cashStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Motivo y justificación de las diferencias',
      ),
      'Reconozco mercancía y dinero reales',
    );
    await tap('Revisar conciliación');
    // First stale revision is detected locally after another official return.
    await nextReturn(e, sale.id);
    await f.pull(url).pullAvailableEvents(limit: 1);
    await tap(
      'Justifico el exceso y confirmo únicamente las recuperaciones realizadas.',
    );
    final effectsBeforeStale =
        (await f.db.select(f.db.saleReconciliationEffects).get()).length;
    await tap('Registrar conciliación');
    expect(find.textContaining('Pendiente de aceptación'), findsNothing);
    expect(
      (await f.db.select(f.db.saleReconciliationEffects).get()).length,
      effectsBeforeStale,
    );
    await tap('Revisar nueva intención tras un rechazo');
    await tap('Revisar conciliación');
    await tap(
      'Justifico el exceso y confirmo únicamente las recuperaciones realizadas.',
    );
    await tap('Registrar conciliación');
    expect(find.textContaining('Pendiente de aceptación'), findsOneWidget);
    await capture('server-reconciliation-pending');
    // Server observes a third official return before this pending declaration.
    await nextReturn(e, sale.id);
    final rejectedReport = await f.push(url).pushPendingEvents();
    expect(rejectedReport.conflicts + rejectedReport.rejected, 1);
    expect(await f.adjustmentStore.hasIncident(sale.id), true);
    final failedAttempt = (await f.db.select(f.db.events).get()).singleWhere(
      (v) =>
          v.eventType == OperacionVentaConciliadaPayload.eventType &&
          v.aggregateId == sale.id,
    );
    expect(['conflict', 'rejected'], contains(failedAttempt.deliveryStatus));
    await f.pull(url).pullAvailableEvents(limit: 1);
    await tap('Consultar estado actualizado');
    await tap('Revisar nueva intención tras un rechazo');
    await tap('Revisar conciliación');
    await tap(
      'Justifico el exceso y confirmo únicamente las recuperaciones realizadas.',
    );
    await tap('Registrar conciliación');
    final pending = (await f.history.pendingEvents()).single;
    expect(pending.eventId, isNot(failedAttempt.eventId));
    await pushAll(f);
    await tap('Consultar estado actualizado');
    await tester.scrollUntilVisible(
      find.textContaining('Resuelta por'),
      -300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Resuelta por'), findsOneWidget);
    await capture('server-reconciliation-resolved');
    final audit = (await f.reconciliationStore.incident(incident.id))!;
    expect(
      audit.attempts
          .singleWhere((a) => a.deliveryStatus == 'delivered')
          .applicationStatus,
      'applied',
    );
    expect(
      audit.attempts.where((a) => a.applicationStatus == 'pending'),
      hasLength(1),
    );
    await e.pull(url).pullAvailableEvents(limit: 1);
    for (final h in [e, f]) {
      final read = (await SaleAdjustmentRepositoryImpl(
        h.db,
      ).watchSales().first).singleWhere((s) => s.original.id == sale.id);
      expect(
        SalesReportsCalculator.ventasTotales(
          ReportPeriod.day(read.original.createdAt.toLocal()),
          [read.original.withAdjustments(read)],
        ),
        BigInt.zero,
      );
      final state = await h.adjustmentStore.readDeliveryState();
      expect(state.inventory[ids.resourceId]!.recorded, BigInt.from(11));
      expect(state.inventory[ids.resourceId]!.localDifference, BigInt.zero);
      expect(
        (await SaleAdjustmentRepositoryImpl(h.db).watchSales().first)
            .singleWhere((s) => s.original.id == sale.id)
            .officialRevision,
        3,
      );
    }
    await f.pull(url).pullAvailableEvents(limit: 1);
    expect(
      (await f.adjustmentStore.readDeliveryState())
          .inventory[ids.resourceId]!
          .recorded,
      BigInt.from(11),
    );
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    link.close();
    for (final h in clients) {
      await h.config.dispose();
      await h.db.close();
    }
  }
}

class _SwitchableLink extends http.BaseClient {
  bool online = true;
  final _client = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!online) throw const SocketException('Client disconnected');
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
