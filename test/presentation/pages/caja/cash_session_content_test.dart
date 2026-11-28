import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/caja/cash_movement.dart';
import 'package:pos_flutter/domain/caja/cash_session.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_session_content.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';

class _Sales implements ConfirmedSaleRepository {
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value([]);
}

CashMovement _movement(
  String id,
  DateTime? date, {
  String? saleId,
  int sequence = 1,
}) => CashMovement(
  id: id,
  eventId: 'event-$id',
  direction: 'in',
  amountMinor: 100,
  sourceType: saleId == null ? 'financial_entry' : 'sale_payment',
  sourceId: 'source-$id',
  deliveryStatus: 'not_required',
  createdAt: date,
  localSequence: sequence,
  saleId: saleId,
);

CashSession _session(List<CashMovement> movements, {bool closed = false}) =>
    CashSession(
      id: 'session',
      deviceId: 'device',
      openedByUserId: 'user',
      status: closed ? 'closed' : 'open',
      openedAtMs: DateTime(2026, 11, 23, 8).millisecondsSinceEpoch,
      closedAtMs: closed
          ? DateTime(2026, 11, 23, 20).millisecondsSinceEpoch
          : null,
      countedMinor: closed ? 200 : null,
      openingMinor: 0,
      openingEventId: 'opening',
      lastEventId: 'last',
      deliveryStatus: 'not_required',
      movements: closed ? [] : movements,
      closedMovements: closed ? movements : null,
      closedDifferenceMinor: closed ? BigInt.zero : null,
    );

Future<void> _pump(WidgetTester tester, CashSession session) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CashSessionContent(session: session),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final closed in [false, true]) {
    testWidgets(
      'ordena por fecha descendente y muestra hora local, cerrado=$closed',
      (tester) async {
        final movements = [
          _movement('z', DateTime(2026, 11, 23, 9, 15, 30).toUtc()),
          _movement('a', DateTime(2026, 11, 23, 18, 45, 10).toUtc()),
          _movement('m', DateTime(2026, 11, 23, 12)),
        ];
        await _pump(tester, _session(movements, closed: closed));
        final tiles = tester.widgetList<ExpansionTile>(
          find.byType(ExpansionTile),
        );
        expect(tiles.map((tile) => tile.key), [
          const ValueKey('cash-movement-a'),
          const ValueKey('cash-movement-m'),
          const ValueKey('cash-movement-z'),
        ]);
        expect(find.textContaining('23/11/2026 18:45:10'), findsOneWidget);
        expect(find.textContaining('23/11/2026 09:15:30'), findsOneWidget);
        expect(movements.first.id, 'z');
      },
    );
  }

  testWidgets('desempata movimientos del mismo segundo por orden de registro', (
    tester,
  ) async {
    final date = DateTime(2026, 11, 23, 10);
    await _pump(
      tester,
      _session([
        _movement('z', date, sequence: 1),
        _movement('a', date, sequence: 2),
      ], closed: true),
    );
    expect(
      tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .map((t) => t.key),
      [const ValueKey('cash-movement-a'), const ValueKey('cash-movement-z')],
    );
  });

  testWidgets('abre el ticket de la venta y permite volver al corte', (
    tester,
  ) async {
    getIt.registerSingleton<ConfirmedSaleRepository>(_Sales());
    addTearDown(() => getIt.unregister<ConfirmedSaleRepository>());
    await _pump(
      tester,
      _session([
        _movement('sale', DateTime(2026, 11, 23, 10), saleId: 'sale-id'),
      ], closed: true),
    );
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ver ticket'));
    await tester.tap(find.text('Ver ticket'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SaleReceiptScreen>(find.byType(SaleReceiptScreen)).saleId,
      'sale-id',
    );
    await tester.tap(find.text('Volver al corte'));
    await tester.pumpAndSettle();
    expect(find.byType(CashSessionContent), findsOneWidget);
  });

  testWidgets(
    'un movimiento sin venta no ofrece ticket y tolera fecha ausente',
    (tester) async {
      await _pump(tester, _session([_movement('entry', null)], closed: true));
      expect(find.textContaining('Fecha no disponible'), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('Ver ticket'), findsNothing);
    },
  );
}
