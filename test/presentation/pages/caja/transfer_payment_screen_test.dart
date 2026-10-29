import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';

class _Sales implements VentaCommandService {
  final commands = <ConfirmarVentaCommand>[];
  final result = Completer<String>();
  @override
  Future<String> confirmar(ConfirmarVentaCommand c) {
    commands.add(c);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'transferencia habilitada sin cliente, límite, doble toque y fallo conserva captura',
    (tester) async {
      final service = _Sales();
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentMethodScreen(
            totalMinor: 2000,
            saleId: 'sale',
            expectedDraftEventId: 'draft',
            commandService: service,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('payment_tab_transfer')));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodScreen), findsOneWidget);
      expect(find.text('Confirmar transferencia'), findsOneWidget);
      final reference = find.byKey(const Key('transfer_reference_input'));
      await tester.enterText(reference, 'x' * 501);
      await tester.tap(find.text('Confirmar transferencia'));
      await tester.pumpAndSettle();
      expect(service.commands, isEmpty);
      await tester.enterText(reference, '  BANCO  ');
      await tester.tap(find.text('Confirmar transferencia'));
      await tester.tap(find.text('Confirmar transferencia'));
      await tester.pumpAndSettle();
      expect(service.commands, hasLength(1));
      expect(service.commands.single.paymentMethod, 'transfer');
      expect(service.commands.single.paymentReference, '  BANCO  ');
      expect(service.commands.single.clienteId, isNull);
      service.result.completeError(StateError('Fallo de prueba'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fallo de prueba'), findsOneWidget);
      expect(find.text('  BANCO  '), findsOneWidget);
    },
  );
}
