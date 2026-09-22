import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/creditos/account_entry.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/informes/widgets/collections_report_card.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';

void main() {
  testWidgets('cobros excluye crédito, cuenta abonos y no suma cambio', (
    tester,
  ) async {
    final day = DateTime(2026, 9, 21);
    ConfirmedSale sale(String method) => ConfirmedSale(
      id: method,
      createdAt: day,
      totalMinor: 2000,
      receivedMinor: method == 'cash' ? 5000 : 0,
      changeMinor: method == 'cash' ? 3000 : 0,
      currency: 'MXN',
      deliveryStatus: 'not_required',
      reason: null,
      items: [],
      paymentMethod: method,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionsReportCard(
            period: ReportPeriod.day(day),
            sales: [sale('cash'), sale('credit')],
            payments: Stream.value([
              AccountEntry(
                id: 'a',
                eventId: 'e',
                amountMinor: 1000,
                occurredAtMs: day.millisecondsSinceEpoch,
                isPayment: true,
                deliveryStatus: 'not_required',
              ),
              AccountEntry(
                id: 'b',
                eventId: 'f',
                amountMinor: 10000,
                occurredAtMs: day
                    .subtract(const Duration(days: 1))
                    .millisecondsSinceEpoch,
                isPayment: true,
                deliveryStatus: 'not_required',
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(r'$30.00 MXN'), findsOneWidget);
  });
}
