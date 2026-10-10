import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/quotation_already_linked_exception.dart';
import 'package:pos_flutter/domain/ventas/sale_draft.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotation_ticket_screen.dart';

import '../../../support/fake_sale_draft_repository.dart';
import '../../../support/fake_producto_repository.dart';
import '../../../support/pump_receipt_image.dart';
import '../../../support/quotation_ui_fixtures.dart';
import '../../../support/sale_draft_fixtures.dart';

void main() {
  testWidgets('Cotizar vacío o sin revisión está deshabilitado', (
    tester,
  ) async {
    for (final draft in [
      null,
      SaleDraft(id: 'empty', lastEventId: 'revision', totalMinor: 0, items: []),
      sampleSale(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CajaScreen(
              productoRepository: FakeProductoRepository(),
              ventaBorradorCommandService: FakeQuotationDraftCommands(),
              key: UniqueKey(),
              saleDraftRepository: FakeSaleDraftRepository(
                () => Stream.value(draft),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Cotizar'),
            )
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets('Cotizar espera commit, captura origen/revisión y bloquea Caja', (
    tester,
  ) async {
    final gate = Completer<void>();
    final commands = FakeQuotationCommands()..gate = gate.future;
    final drafts = FakeQuotationDraftCommands();
    await _caja(tester, commands, drafts: drafts);
    await tester.tap(find.text('Cotizar'));
    await tester.tap(find.text('Cotizar'));
    await tester.tap(find.text('Limpiar venta'));
    await tester.pump();
    expect(commands.saved, hasLength(1));
    expect(commands.saved.single.saleId, 'sale');
    expect(commands.saved.single.expectedDraftEventId, 'draft-event');
    expect(drafts.cleared, isEmpty);
    expect(find.byType(QuotationTicketScreen), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, r'Cobrar: $109.00'),
          )
          .onPressed,
      isNull,
    );
    for (final button in tester.widgetList<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Editar artículo',
      ),
    )) {
      expect(button.onPressed, isNull);
    }
    gate.complete();
    await pumpReceiptImage(tester);
    final ticket = tester.widget<QuotationTicketScreen>(
      find.byType(QuotationTicketScreen),
    );
    expect(ticket.emissionDraft?.saleId, 'sale');
    expect(ticket.emissionDraft?.expectedDraftEventId, 'draft-event');
  });

  testWidgets('fallo al guardar reintenta identidad estable sin abrir ticket', (
    tester,
  ) async {
    final commands = FakeQuotationCommands()..error = StateError('rollback');
    await _caja(tester, commands);
    await tester.tap(find.text('Cotizar'));
    await tester.pumpAndSettle();
    expect(find.byType(QuotationTicketScreen), findsNothing);
    expect(
      find.textContaining('No se pudo guardar la cotización.'),
      findsOneWidget,
    );
    commands.error = null;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cotizar'));
    await pumpReceiptImage(tester);
    expect(commands.saved, hasLength(2));
    expect(identical(commands.saved.first, commands.saved.last), isTrue);
  });

  testWidgets(
    'captura vinculada consulta histórico sin crear otra ni limpiar al cerrar',
    (tester) async {
      final commands = FakeQuotationCommands()
        ..error = const QuotationAlreadyLinkedException('quotation-1');
      final drafts = FakeQuotationDraftCommands();
      await _caja(tester, commands, drafts: drafts);
      await tester.tap(find.text('Cotizar'));
      await pumpReceiptImage(tester);
      final ticket = tester.widget<QuotationTicketScreen>(
        find.byType(QuotationTicketScreen),
      );
      expect(ticket.emissionDraft, isNull);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(CajaScreen), findsOneWidget);
      expect(drafts.cleared, isEmpty);
    },
  );

  testWidgets(
    'volver del ticket y cotizar otra vez consulta el documento vinculado',
    (tester) async {
      final commands = FakeQuotationCommands();
      await _caja(tester, commands);
      await tester.tap(find.text('Cotizar'));
      await pumpReceiptImage(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      commands.error = const QuotationAlreadyLinkedException('quotation-1');
      await tester.tap(find.text('Cotizar'));
      await pumpReceiptImage(tester);
      expect(
        tester
            .widget<QuotationTicketScreen>(find.byType(QuotationTicketScreen))
            .emissionDraft,
        isNull,
      );
      expect(
        commands.saved.first.quotationId,
        isNot(commands.saved.last.quotationId),
      );
    },
  );

  testWidgets(
    'guardado pendiente que finaliza después de dispose no abre ruta',
    (tester) async {
      final gate = Completer<void>();
      final commands = FakeQuotationCommands()..gate = gate.future;
      await _caja(tester, commands);
      await tester.tap(find.text('Cotizar'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(QuotationTicketScreen), findsNothing);
    },
  );

  testWidgets('otra ruta abierta durante guardar impide navegación tardía', (
    tester,
  ) async {
    final gate = Completer<void>();
    final commands = FakeQuotationCommands()..gate = gate.future;
    final navigator = GlobalKey<NavigatorState>();
    await _caja(tester, commands, navigator: navigator);
    await tester.tap(find.text('Cotizar'));
    await tester.pump();
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Otra pantalla')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Otra pantalla'), findsOneWidget);
    expect(find.byType(QuotationTicketScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _caja(
  WidgetTester tester,
  FakeQuotationCommands commands, {
  FakeQuotationDraftCommands? drafts,
  GlobalKey<NavigatorState>? navigator,
}) async {
  final sample = sampleSale();
  final sale = SaleDraft(
    id: sample.id,
    lastEventId: 'draft-event',
    totalMinor: sample.totalMinor,
    items: sample.items,
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: CajaScreen(
          productoRepository: FakeProductoRepository(),
          saleDraftRepository: FakeSaleDraftRepository(
            () => Stream.value(sale),
          ),
          quotationRepository: FakeQuotationRepository(),
          cotizacionCommandService: commands,
          ventaBorradorCommandService: drafts ?? FakeQuotationDraftCommands(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
