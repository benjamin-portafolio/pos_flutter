import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_result.dart';
import 'package:pos_flutter/application/sync/quotation_recovery_line_exception.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_estimate.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_line_estimate.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_status.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotation_detail_screen.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotations_screen.dart';

import '../../../support/quotation_ui_fixtures.dart';

void main() {
  testWidgets(
    'P09: consulta conserva selección con precio/total no disponibles',
    (tester) async {
      final repository = FakeQuotationRepository()
        ..estimateSource = (q) async => QuotationEstimate(
          calculatedAt: DateTime.utc(2026),
          totalMinor: null,
          lines: [
            for (final item in q.items)
              QuotationLineEstimate(
                quotationItemId: item.id,
                issue: 'La variante ya no está disponible.',
              ),
          ],
        );
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationDetailScreen(
            quotationId: 'quotation-1',
            repository: repository,
            commands: FakeQuotationCommands(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Total estimado actual: Total no disponible'),
        findsOneWidget,
      );
      expect(find.textContaining('Precio no disponible'), findsNWidgets(3));
      expect(find.text('Importe no disponible'), findsNWidgets(3));
      expect(find.textContaining('Pan artesanal'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Recuperar en Caja'), 300);
      expect(find.text('Recuperar en Caja'), findsOneWidget);
    },
  );

  testWidgets(
    'Recuperables incluye Disponible y En venta; Todas conserva filtro al regresar',
    (tester) async {
      final repository = FakeQuotationRepository([
        sampleQuotation(id: 'available', date: DateTime(2026, 10, 3)),
        sampleQuotation(
          id: 'active',
          status: QuotationStatus.enVenta,
          date: DateTime(2026, 10, 4),
        ),
        sampleQuotation(id: 'sold', status: QuotationStatus.vendida),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: QuotationsScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(repository.filters, [true]);
      expect(find.textContaining('Vendida'), findsNothing);
      expect(find.textContaining('Disponible'), findsOneWidget);
      expect(find.textContaining('En venta'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('active'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('available'))).dy),
      );
      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vendida'), findsOneWidget);
      expect(find.textContaining(r'$245.00 MXN'), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('sold')));
      await tester.pumpAndSettle();
      expect(find.byType(QuotationDetailScreen), findsOneWidget);
      expect(find.text('Recuperar en Caja'), findsNothing);
      expect(find.text('Continuar venta'), findsNothing);
      await tester.scrollUntilVisible(find.text('Ver venta'), 200);
      expect(find.text('Ver venta'), findsOneWidget);
      expect(find.text('Pan artesanal\nIntegral'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Todas'))
            .selected,
        isTrue,
      );
      expect(repository.filters, [true, false]);
    },
  );

  testWidgets('listado muestra carga, error, reintento y ambos vacíos', (
    tester,
  ) async {
    final controller = StreamController<List<Quotation>>();
    addTearDown(controller.close);
    var calls = 0;
    final repository = FakeQuotationRepository([])
      ..listSource = (_) => calls++ == 0 ? controller.stream : Stream.value([]);
    await tester.pumpWidget(
      MaterialApp(home: QuotationsScreen(repository: repository)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    controller.addError(StateError('SQLite'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudieron cargar las cotizaciones.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('No hay cotizaciones recuperables.'), findsOneWidget);
    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();
    expect(find.text('No hay cotizaciones guardadas.'), findsOneWidget);
  });

  testWidgets(
    'doble toque abre un detalle; recuperar espera commit y devuelve resultado a su dueño',
    (tester) async {
      final gate = Completer<void>();
      final commands = FakeQuotationCommands()..gate = gate.future;
      RecuperarCotizacionResult? received;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  received = await Navigator.of(context)
                      .push<RecuperarCotizacionResult>(
                        MaterialPageRoute(
                          builder: (_) => QuotationsScreen(
                            repository: FakeQuotationRepository(),
                            commands: commands,
                          ),
                        ),
                      );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final open = tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'Cotización quotation-1'),
          )
          .onTap!;
      await tester.tap(find.text('Cotización quotation-1'));
      open();
      await tester.pumpAndSettle();
      expect(find.byType(QuotationDetailScreen), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Recuperar en Caja'), 200);
      await tester.tap(find.text('Recuperar en Caja'));
      await tester.tap(find.text('Recuperar en Caja'));
      await tester.pump();
      expect(commands.recovered, hasLength(1));
      expect(received, isNull);
      expect(find.byType(QuotationDetailScreen), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(received?.saleId, 'recovered-sale');
      expect(find.byType(QuotationsScreen), findsNothing);
    },
  );

  testWidgets('otra captura conserva documento y reintenta la misma identidad', (
    tester,
  ) async {
    final commands = FakeQuotationCommands()
      ..error = StateError(
        'Resuelve la otra captura de Caja antes de recuperar esta cotización.',
      );
    await _detail(tester, commands: commands);
    await tester.tap(find.text('Recuperar en Caja'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Resuelve la otra captura'), findsOneWidget);
    expect(find.text('Pan artesanal\nIntegral'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Recuperar en Caja'), 200);
    await tester.tap(find.text('Recuperar en Caja'));
    await tester.pumpAndSettle();
    expect(commands.recovered, hasLength(2));
    expect(identical(commands.recovered[0], commands.recovered[1]), isTrue);
    expect(
      commands.recovered.first.expectedQuotationEventId,
      'quotation-event',
    );
  });

  for (final reason in [
    'El artículo ya no está disponible.',
    'La unidad está ausente, inactiva o cambió su interpretación.',
  ]) {
    testWidgets('error por línea: $reason', (tester) async {
      final commands = FakeQuotationCommands()
        ..error = QuotationRecoveryLineException('measured-line', reason);
      await _detail(tester, commands: commands);
      await tester.tap(find.text('Recuperar en Caja'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('$reason La cotización se conserva guardada.'),
        findsOneWidget,
      );
      expect(find.textContaining('Café de especialidad'), findsNWidgets(2));
      expect(find.text('Ver ticket'), findsOneWidget);
    });
  }

  testWidgets('Recuperar vuelve a Caja después del commit', (tester) async {
    final commands = FakeQuotationCommands();
    await _detail(tester, commands: commands);
    await tester.tap(find.text('Recuperar en Caja'));
    await tester.pumpAndSettle();
    expect(commands.recovered, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Continuar usa comando actual; los cambios de estado vienen del repositorio',
    (tester) async {
      final controller = StreamController<Quotation?>();
      addTearDown(controller.close);
      final repository = FakeQuotationRepository()
        ..documentSource = (_) => controller.stream;
      final commands = FakeQuotationCommands()
        ..error = StateError('No disponible');
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationDetailScreen(
            quotationId: 'quotation-1',
            repository: repository,
            commands: commands,
          ),
        ),
      );
      controller.add(sampleQuotation(status: QuotationStatus.enVenta));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Continuar venta'), 200);
      await tester.tap(find.text('Continuar venta'));
      await tester.pumpAndSettle();
      expect(commands.recovered.single.quotationId, 'quotation-1');
      expect(find.text('En venta'), findsOneWidget);
      controller.add(sampleQuotation(status: QuotationStatus.vendida));
      await tester.pumpAndSettle();
      expect(find.text('Vendida'), findsOneWidget);
      expect(find.text('Continuar venta'), findsNothing);
      await tester.scrollUntilVisible(find.text('Ver venta'), 200);
      expect(find.text('Ver venta'), findsOneWidget);
    },
  );

  testWidgets('Vendida abre su recibo sin recuperar', (tester) async {
    final commands = FakeQuotationCommands();
    await _detail(
      tester,
      commands: commands,
      quotation: sampleQuotation(status: QuotationStatus.vendida),
      sales: _Sales(),
    );
    await tester.scrollUntilVisible(find.text('Ver venta'), 200);
    await tester.tap(find.text('Ver venta'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SaleReceiptScreen>(find.byType(SaleReceiptScreen)).saleId,
      'linked-sale',
    );
    expect(commands.recovered, isEmpty);
  });

  testWidgets('respuesta histórica sin captura no navega', (tester) async {
    final commands = FakeQuotationCommands()
      ..result = RecuperarCotizacionResult(
        saleId: 'cleared',
        eventId: 'event',
        continued: true,
        draftAvailable: false,
      );
    await _detail(tester, commands: commands);
    await tester.tap(find.text('Recuperar en Caja'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Esa captura ya no está disponible.'),
      findsOneWidget,
    );
    expect(find.byType(QuotationDetailScreen), findsOneWidget);
  });

  testWidgets('recuperación tardía tras salir no navega ni actualiza dispose', (
    tester,
  ) async {
    final gate = Completer<void>();
    final commands = FakeQuotationCommands()..gate = gate.future;
    await _detail(tester, commands: commands);
    await tester.tap(find.text('Recuperar en Caja'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalle contempla carga, ausencia, error y reintento', (
    tester,
  ) async {
    final controller = StreamController<Quotation?>();
    addTearDown(controller.close);
    var calls = 0;
    final repository = FakeQuotationRepository()
      ..documentSource = (_) =>
          calls++ == 0 ? controller.stream : Stream.value(null);
    await tester.pumpWidget(
      MaterialApp(
        home: QuotationDetailScreen(
          quotationId: 'absent',
          repository: repository,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    controller.addError(StateError('lectura'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar la cotización.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('No se encontró la cotización.'), findsOneWidget);
  });

  testWidgets(
    'historial y detalle admiten UUID, nombres largos y texto ampliado',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final quotation = sampleQuotation(
        id: '12345678-1234-4234-8234-123456789012',
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: QuotationsScreen(
            repository: FakeQuotationRepository([quotation]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cotización ${quotation.id}'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Recuperar en Caja'), 200);
      expect(find.text('Recuperar en Caja'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _detail(
  WidgetTester tester, {
  required FakeQuotationCommands commands,
  Quotation? quotation,
  ConfirmedSaleRepository? sales,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: QuotationDetailScreen(
        quotationId: 'quotation-1',
        repository: FakeQuotationRepository([quotation ?? sampleQuotation()]),
        commands: commands,
        sales: sales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final action = find.text(
    quotation?.status == QuotationStatus.vendida
        ? 'Ver venta'
        : 'Recuperar en Caja',
  );
  await tester.scrollUntilVisible(action, 200);
  await tester.pumpAndSettle();
}

class _Sales implements ConfirmedSaleRepository {
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value([]);
}
