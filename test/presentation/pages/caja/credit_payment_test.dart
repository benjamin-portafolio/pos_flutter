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
    'crédito no abre selector al entrar, exige cliente y confirma una sola vez',
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
      await tester.tap(find.byKey(const Key('payment_tab_credit')));
      await tester.pumpAndSettle();
      expect(find.byType(ClientePickerScreen), findsNothing);
      expect(sales.commands, isEmpty);
      expect(find.text('Sin cliente seleccionado'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Confirmar crédito');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.tap(find.byTooltip('Buscar cliente'));
      await tester.pumpAndSettle();
      expect(find.byType(ClientePickerScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), '555');
      await tester.pumpAndSettle();
      expect(find.text('Luis'), findsNothing);
      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();

      expect(find.byType(ClientePickerScreen), findsNothing);
      expect(find.text('Ana'), findsWidgets);
      expect(find.text('555'), findsWidgets);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Confirmar venta a crédito'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Confirmar crédito'),
        ),
      );
      await tester.pumpAndSettle();
      expect(sales.commands, hasLength(1));
      expect(sales.commands.single.clienteId, 'ana');
      expect(sales.commands.single.paymentMethod, 'credit');
      expect(sales.commands.single.receivedMinor, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Registrando…'),
            )
            .onPressed,
        isNull,
      );
      sales.result.completeError(StateError('El borrador cambió'));
      await tester.pumpAndSettle();
      expect(find.textContaining('El borrador cambió'), findsOneWidget);
      expect(find.text('Ana'), findsWidgets);
      expect(find.text('Confirmar crédito'), findsOneWidget);
    },
  );
}
