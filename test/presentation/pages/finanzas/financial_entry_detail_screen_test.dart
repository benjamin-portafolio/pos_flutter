import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_entry.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';
import 'package:pos_flutter/presentation/pages/finanzas/financial_entry_detail_screen.dart';
import 'package:pos_flutter/presentation/pages/finanzas/widgets/financial_delivery_status_chip.dart';

FinancialEntry _entry({
  String deliveryStatus = 'delivered',
  String? rejectionReason,
  String? notes = 'Nota de prueba',
  String? reference = 'REF-99',
}) {
  return FinancialEntry(
    id: 'entry-1',
    eventId: 'event-1',
    categoryId: 'cat-renta',
    categoryNameSnapshot: 'Renta',
    direction: FinancialDirection.expense,
    nature: FinancialNature.operating,
    amountMinor: 125000,
    currency: 'MXN',
    method: 'cash',
    occurredAtMs: DateTime.utc(2026, 9, 25, 18).millisecondsSinceEpoch,
    notes: notes,
    reference: reference,
    deliveryStatus: deliveryStatus,
    rejectionReason: rejectionReason,
    userId: 'user',
    deviceId: 'tablet',
  );
}

/// Pinta el detalle con una superficie alta para que la tarjeta de
/// trazabilidad (fila "Entrega") entre en el viewport: el ListView es perezoso
/// y en 600 px de alto la rechazada queda bajo el fold.
Future<void> _pumpDetail(
  WidgetTester tester,
  FinancialEntry entry,
) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: FinancialEntryDetailScreen(entry: entry)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('detalle muestra monto, clasificación, método, fecha y notas',
      (tester) async {
    await _pumpDetail(tester, _entry());

    // Monto en headline + fila "Monto" (SelectableText).
    expect(find.text(r'$1250.00 MXN'), findsNWidgets(2));
    expect(find.text('Renta'), findsOneWidget);
    expect(find.text('Gasto'), findsOneWidget);
    expect(find.text('Operativo'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Nota de prueba'), findsOneWidget);
    expect(find.text('REF-99'), findsOneWidget);
    // Trazabilidad completa.
    expect(find.text('Trazabilidad'), findsOneWidget);
    expect(find.text('event-1'), findsOneWidget);
    expect(find.text('user'), findsOneWidget);
    expect(find.text('tablet'), findsOneWidget);
    // Estado entregado: chip + fila "Entrega".
    expect(find.text('Sincronizada'), findsNWidgets(2));
  });

  testWidgets('rechazo: motivo visible y el dinero sigue visible',
      (tester) async {
    await _pumpDetail(
      tester,
      _entry(
        deliveryStatus: 'rejected',
        rejectionReason: 'El servidor rechazó el registro.',
      ),
    );

    expect(find.text(r'$1250.00 MXN'), findsNWidgets(2));
    expect(find.text('El servidor rechazó el registro.'), findsOneWidget);
    expect(find.text('Requiere atención'), findsNWidgets(2));
  });

  testWidgets('conflicto también muestra atención y motivo por defecto',
      (tester) async {
    await _pumpDetail(
      tester,
      _entry(deliveryStatus: 'conflict', rejectionReason: null),
    );

    expect(find.text('Incidencia de sincronización.'), findsOneWidget);
    expect(find.text('Requiere atención'), findsNWidgets(2));
  });

  testWidgets('state chip: local, pendiente, incidencia y desconocido',
      (tester) async {
    Widget chip(String status, [String? reason]) => MaterialApp(
      home: Scaffold(
        body: FinancialDeliveryStatusChip(status: status, rejectionReason: reason),
      ),
    );

    await tester.pumpWidget(chip('not_required'));
    expect(find.text('Registro local'), findsOneWidget);

    await tester.pumpWidget(chip('pending'));
    expect(find.text('Pendiente de sincronizar'), findsOneWidget);

    await tester.pumpWidget(chip('rejected', 'Motivo A'));
    expect(find.text('Requiere atención'), findsOneWidget);

    await tester.pumpWidget(chip('desconocido'));
    expect(find.text('Estado desconocido'), findsOneWidget);
  });

  testWidgets('evento con notas/referencia nulos no muestra esas filas',
      (tester) async {
    await _pumpDetail(tester, _entry(notes: null, reference: null));

    expect(find.text('Nota'), findsNothing);
    expect(find.text('Referencia'), findsNothing);
    expect(find.text(r'$1250.00 MXN'), findsNWidgets(2));
  });
}