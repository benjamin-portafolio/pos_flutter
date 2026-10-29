import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/domain/clientes/cliente.dart';
import 'package:pos_flutter/domain/repositories/cliente_repository.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_picker_screen.dart';

class _Sales implements VentaCommandService {
  final commands = <ConfirmarVentaCommand>[];
  var result = Completer<String>();

  @override
  Future<String> confirmar(ConfirmarVentaCommand command) {
    commands.add(command);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Clients implements ClienteRepository {
  @override
  Stream<List<Cliente>> watchClientes() =>
      Stream.value(const [Cliente(id: 'ana', nombre: 'Ana', telefono: '555')]);
}

void main() {
  testWidgets('abre en efectivo, enfoca el campo y Enter vacío paga exacto', (
    tester,
  ) async {
    final sales = _Sales();
    await _pump(tester, service: sales);
    expect(find.byKey(const Key('cash_payment_content')), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Transferencia'), findsOneWidget);
    expect(find.text('Crédito'), findsOneWidget);
    expect(find.text('Tarjeta'), findsOneWidget);
    expect(find.textContaining('Total a cobrar'), findsOneWidget);
    final field = tester.widget<TextField>(_cashInput);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, isEmpty);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(sales.commands, hasLength(1));
    expect(sales.commands.single.paymentMethod, 'cash');
    expect(sales.commands.single.receivedMinor, isNull);
    expect(sales.commands.single.paymentReference, isNull);
    expect(sales.commands.single.clienteId, isNull);

    // Mientras registra no se puede cambiar de método ni volver a confirmar.
    await tester.tap(find.byKey(const Key('payment_tab_transfer')));
    await tester.pump();
    expect(find.byKey(const Key('transfer_payment_content')), findsNothing);
    await tester.pageBack();
    await tester.pump();
    expect(find.byType(PaymentMethodScreen), findsOneWidget);
    sales.result.completeError(StateError('guardado falló'));
    await tester.pumpAndSettle();
    expect(find.textContaining('guardado falló'), findsOneWidget);
    expect(_cashInput, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Recibido por efectivo'),
          )
          .onPressed,
      isNotNull,
    );
    sales.result = Completer<String>();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(sales.commands, hasLength(2));
    sales.result.completeError(StateError('segundo intento explícito'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Enter con importe suficiente confirma y con insuficiente avisa',
    (tester) async {
      final sales = _Sales();
      await _pump(tester, service: sales, totalMinor: 10000);
      await tester.enterText(_cashInput, '99');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(sales.commands, isEmpty);
      expect(
        find.text('El efectivo recibido es insuficiente.'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(_cashInput).focusNode!.hasFocus, isTrue);

      await tester.enterText(_cashInput, '100');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(sales.commands, hasLength(1));
      expect(sales.commands.single.receivedMinor, 10000);
      sales.result.completeError(StateError('fin de prueba'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('el Enter de apertura y sus repeticiones no confirman', (
    tester,
  ) async {
    final sales = _Sales();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await _pump(tester, service: sales, consumeOpeningEnter: true);
    expect(_cashInput, findsOneWidget);
    expect(tester.widget<TextField>(_cashInput).focusNode!.hasFocus, isTrue);
    await tester.showKeyboard(_cashInput);
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sales.commands, isEmpty);
    expect(tester.widget<TextField>(_cashInput).focusNode!.hasFocus, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sales.commands, hasLength(1));
    sales.result.completeError(StateError('fin de prueba'));
    await tester.pumpAndSettle();
  });

  testWidgets('cambiar pestañas conserva cliente, efectivo y referencia', (
    tester,
  ) async {
    final sales = _Sales();
    await _pump(tester, service: sales, clientes: _Clients());
    await tester.tap(find.byTooltip('Buscar cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.enterText(_cashInput, '25.50');
    await tester.pump();

    await tester.tap(find.byKey(const Key('payment_tab_transfer')));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentMethodScreen), findsOneWidget);
    expect(find.byKey(const Key('transfer_payment_content')), findsOneWidget);
    expect(find.text('Ana'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('transfer_reference_input')),
      'REF-1',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('payment_tab_credit')));
    await tester.pumpAndSettle();
    expect(find.byType(ClientePickerScreen), findsNothing);
    expect(find.text('Ana'), findsWidgets);
    expect(sales.commands, isEmpty);

    await tester.tap(find.byKey(const Key('payment_tab_card')));
    await tester.pumpAndSettle();
    expect(
      find.text('El pago con tarjeta aún no está disponible'),
      findsOneWidget,
    );
    expect(find.text('Ana'), findsWidgets);

    await tester.tap(find.byKey(const Key('payment_tab_cash')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_cashInput).controller!.text, '25.50');
    expect(tester.widget<TextField>(_cashInput).focusNode!.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('payment_tab_transfer')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('transfer_reference_input')),
          )
          .controller!
          .text,
      'REF-1',
    );
    expect(sales.commands, isEmpty);
  });

  testWidgets('tarjeta informa y no ofrece confirmar ni registrar', (
    tester,
  ) async {
    final sales = _Sales();
    await _pump(tester, service: sales);
    await tester.tap(find.byKey(const Key('payment_tab_card')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Total a cobrar'), findsOneWidget);
    expect(find.textContaining(r'$100.00'), findsOneWidget);
    expect(
      find.text('El pago con tarjeta aún no está disponible'),
      findsOneWidget,
    );
    expect(find.text('Recibido por efectivo'), findsNothing);
    expect(find.text('Confirmar transferencia'), findsNothing);
    expect(find.text('Confirmar crédito'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(sales.commands, isEmpty);
  });

  testWidgets('Enter en referencia conserva salto de línea y no confirma', (
    tester,
  ) async {
    final sales = _Sales();
    await _pump(tester, service: sales);
    await tester.tap(find.byKey(const Key('payment_tab_transfer')));
    await tester.pumpAndSettle();
    final reference = find.byKey(const Key('transfer_reference_input'));
    await tester.enterText(reference, 'Banco\nReferencia');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    expect(sales.commands, isEmpty);
    expect(
      tester.widget<TextFormField>(reference).controller!.text,
      'Banco\nReferencia',
    );
  });

  testWidgets('importe fuera de rango no confirma ni pierde la captura', (
    tester,
  ) async {
    final sales = _Sales();
    await _pump(tester, service: sales);
    await tester.enterText(_cashInput, '90071992547410');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(sales.commands, isEmpty);
    expect(
      find.text('El efectivo recibido excede el límite permitido.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(_cashInput).controller!.text,
      '90071992547410',
    );
    expect(tester.widget<TextField>(_cashInput).focusNode!.hasFocus, isTrue);
  });
}

Finder get _cashInput => find.byKey(const Key('cash_received_input'));

Future<void> _pump(
  WidgetTester tester, {
  required _Sales service,
  int totalMinor = 10000,
  bool consumeOpeningEnter = false,
  ClienteRepository? clientes,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PaymentMethodScreen(
        totalMinor: totalMinor,
        saleId: 'sale',
        expectedDraftEventId: 'draft',
        commandService: service,
        clienteRepository: clientes,
        consumeOpeningEnter: consumeOpeningEnter,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
