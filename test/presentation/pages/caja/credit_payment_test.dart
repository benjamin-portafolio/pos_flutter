import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/domain/clientes/cliente.dart';
import 'package:pos_flutter/domain/repositories/cliente_repository.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_picker_screen.dart';

class _Clients implements ClienteRepository {
  @override
  Stream<List<Cliente>> watchClientes() => Stream.value(const [
    Cliente(id: 'ana', nombre: 'Ana', telefono: '555'),
    Cliente(id: 'luis', nombre: 'Luis', telefono: null),
  ]);
}

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
    'crédito exige seleccionar cliente, filtra y confirma una sola vez',
    (tester) async {
      final sales = _Sales();
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentMethodScreen(
            totalMinor: 2000,
            saleId: 'sale',
            expectedDraftEventId: 'draft',
            clienteRepository: _Clients(),
            commandService: sales,
          ),
        ),
      );
      await tester.tap(find.text('Crédito del cliente'));
      await tester.pumpAndSettle();
      expect(find.byType(ClientePickerScreen), findsOneWidget);
      expect(sales.commands, isEmpty);
      await tester.enterText(find.byType(TextField), '555');
      await tester.pumpAndSettle();
      expect(find.text('Luis'), findsNothing);
      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crédito del cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar crédito'));
      await tester.pumpAndSettle();
      expect(sales.commands, hasLength(1));
      expect(sales.commands.single.clienteId, 'ana');
      expect(sales.commands.single.paymentMethod, 'credit');
      expect(sales.commands.single.receivedMinor, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Registrando…'),
            )
            .onPressed,
        isNull,
      );
      sales.result.completeError(StateError('El borrador cambió'));
      await tester.pumpAndSettle();
      expect(find.textContaining('El borrador cambió'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Crédito del cliente'), findsOneWidget);
    },
  );
}
