import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_payment_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';
import '../../../support/pump_receipt_image.dart';

class _Service implements VentaCommandService {
  final commit = Completer<String>();
  final commands = <ConfirmarVentaCommand>[];
  @override
  Future<String> confirmar(ConfirmarVentaCommand command) {
    commands.add(command);
    return commit.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements ConfirmedSaleRepository {
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value([
    ConfirmedSale(
      id: 'sale',
      createdAt: DateTime(2026),
      totalMinor: 10000,
      receivedMinor: 20000,
      changeMinor: 10000,
      currency: 'MXN',
      deliveryStatus: 'pending',
      reason: null,
      items: [],
    ),
  ]);
}

void main() {
  setUp(() => getIt.registerSingleton<ConfirmedSaleRepository>(_Repository()));
  tearDown(() => getIt.unregister<ConfirmedSaleRepository>());
  for (final input in ['', '100', '200']) {
    testWidgets('confirma $input después de commit y bloquea doble toque', (
      tester,
    ) async {
      final service = _Service();
      await tester.pumpWidget(
        MaterialApp(
          home: CashPaymentScreen(
            totalMinor: 10000,
            saleId: 'sale',
            expectedDraftEventId: 'draft-revision',
            commandService: service,
          ),
        ),
      );
      if (input.isNotEmpty) {
        await tester.enterText(find.byType(TextField), input);
      }
      await tester.tap(find.text('Recibido por efectivo'));
      await tester.pump();
      expect(find.text('Registrando…'), findsOneWidget);
      expect(find.byType(SaleReceiptScreen), findsNothing);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrando…'),
      );
      expect(button.onPressed, isNull);
      expect(service.commands, hasLength(1));
      expect(service.commands.single.saleId, 'sale');
      expect(service.commands.single.expectedDraftEventId, 'draft-revision');
      expect(
        service.commands.single.receivedMinor,
        input.isEmpty ? null : int.parse(input) * 100,
      );
      service.commit.complete('confirmed-event');
      await pumpReceiptImage(tester);
      expect(find.byType(SaleReceiptScreen), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Nueva venta'), findsOneWidget);
    });
  }
  testWidgets(
    'insuficiente no confirma; fallo conserva captura para revisión',
    (tester) async {
      final service = _Service();
      await tester.pumpWidget(
        MaterialApp(
          home: CashPaymentScreen(
            totalMinor: 10000,
            saleId: 'sale',
            expectedDraftEventId: 'draft',
            commandService: service,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '99');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Recibido por efectivo'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '200');
      await tester.pump();
      await tester.tap(find.text('Recibido por efectivo'));
      service.commit.completeError(StateError('El borrador cambió'));
      await tester.pumpAndSettle();
      expect(find.textContaining('El borrador cambió'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.byType(SaleReceiptScreen), findsNothing);
    },
  );
}
