import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/cobros/collection_entry.dart';
import 'package:pos_flutter/presentation/pages/informes/widgets/collections_report_card.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';

void main() {
  testWidgets('desglose por período y movimientos con trazabilidad', (
    tester,
  ) async {
    final day = DateTime(2026, 9, 21);
    CollectionEntry entry(
      String id,
      String method,
      int amount, {
      DateTime? date,
    }) => CollectionEntry(
      id: id,
      eventId: 'event-$id',
      amountMinor: amount,
      method: method,
      date: date ?? day,
      origin: 'customer_payment',
      userId: 'Ana',
      deviceId: 'Tablet 1',
      deliveryStatus: 'pending',
      reference: 'REF-$id',
      clienteId: 'cliente-1',
      clienteNombre: 'Luis',
    );
    final stream = Stream.value([
      entry('a', 'cash', 2000),
      entry('b', 'transfer', 3000),
      entry('c', 'transfer', 1000, date: day.subtract(const Duration(days: 1))),
    ]).asBroadcastStream();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionsReportCard(
            period: ReportPeriod.day(day),
            collections: stream,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(r'$20.00 MXN'), findsOneWidget);
    expect(find.text(r'$30.00 MXN'), findsOneWidget);
    expect(find.text(r'$50.00 MXN'), findsOneWidget);
    await tester.tap(find.text('Transferencia'));
    await tester.pumpAndSettle();
    expect(find.textContaining(r'$30.00 MXN · Transferencia'), findsOneWidget);
    expect(find.textContaining(r'$20.00'), findsNothing);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.textContaining('Referencia: REF-b'), findsOneWidget);
    expect(find.textContaining('Dispositivo: Tablet 1'), findsOneWidget);
    expect(find.textContaining('Usuario: Ana'), findsOneWidget);
    expect(find.textContaining('Cliente: Luis'), findsOneWidget);
    expect(find.textContaining('Pendiente de sincronizar'), findsOneWidget);
  });
}
