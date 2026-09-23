import 'package:pos_flutter/presentation/pages/gestion_clientes/customer_account_receipt_image_generator.dart';
import 'dart:async';
import 'package:pos_flutter/domain/repositories/cliente_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/clientes/cliente.dart';
import 'package:pos_flutter/domain/creditos/account_entry.dart';
import 'package:pos_flutter/domain/creditos/customer_account.dart';
import 'package:pos_flutter/domain/repositories/customer_account_repository.dart';
import 'package:pos_flutter/application/commands/creditos/credito_command_service.dart';
import 'package:pos_flutter/application/commands/creditos/registrar_abono_command.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_account_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/registrar_abono_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/customer_account_display.dart';

class _Clientes implements ClienteRepository {
  @override
  Stream<List<Cliente>> watchClientes() => Stream.value([cliente]);
}

class _Account implements CustomerAccountRepository {
  @override
  Stream<CustomerAccount> watchAccount(String clienteId) => Stream.value(
    CustomerAccount([
      const AccountEntry(
        id: 'v1',
        eventId: 'e1',
        amountMinor: 2000,
        occurredAtMs: 1000,
        isPayment: false,
        deliveryStatus: 'not_required',
      ),
      const AccountEntry(
        id: 'a1',
        eventId: 'e2',
        amountMinor: 1000,
        occurredAtMs: 2000,
        isPayment: true,
        deliveryStatus: 'pending',
        method: 'cash',
      ),
    ]),
  );
  @override
  Stream<List<AccountEntry>> watchPayments() => Stream.value([]);
}

class _Service implements CreditoCommandService {
  final result = Completer<String>();
  final commands = <RegistrarAbonoCommand>[];
  @override
  Future<String> registrarAbono(RegistrarAbonoCommand c) {
    commands.add(c);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const cliente = Cliente(id: 'ana', nombre: 'Ana', telefono: '555');
void main() {
  testWidgets('genera estado de cuenta completo como PNG', (tester) async {
    final account = await _Account().watchAccount('ana').first;
    final text = CustomerAccountDisplay.statement('Ana', account);
    final bytes = await tester.runAsync(
      () => CustomerAccountReceiptImageGenerator().generate(text),
    );
    expect(bytes!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(bytes.length, greaterThan(1000));
  });
  testWidgets('muestra saldo, historial, detalle y estado de cuenta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClienteAccountScreen(
          cliente: cliente,
          repository: _Account(),
          clienteRepository: _Clientes(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Debe'), findsOneWidget);
    expect(find.text(r'-$10.00'), findsOneWidget);
    expect(find.text('1 ventas pendientes'), findsOneWidget);
    expect(find.text('555'), findsOneWidget);
    await tester.tap(find.textContaining('Abono ·'));
    await tester.pumpAndSettle();
    expect(find.text('Método: Efectivo'), findsOneWidget);
    await tester.tap(find.text('Ver / compartir estado de cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Aplicado a v1'), findsOneWidget);
  });
  testWidgets('abono valida importe, conserva id y bloquea doble guardado', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrarAbonoScreen(cliente: cliente, commandService: service),
      ),
    );
    await tester.tap(find.text('Guardar abono'));
    await tester.pumpAndSettle();
    expect(service.commands, isEmpty);
    await tester.enterText(find.byKey(const Key('abono_importe')), '10.50');
    await tester.tap(find.text('Guardar abono'));
    await tester.pumpAndSettle();
    expect(service.commands.single.amountMinor, 1050);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardando…'))
          .onPressed,
      isNull,
    );
    service.result.completeError(StateError('Disco lleno'));
    await tester.pumpAndSettle();
    expect(find.text('10.50'), findsOneWidget);
    expect(find.textContaining('Disco lleno'), findsOneWidget);
  });
  test(
    'estado de cuenta incluye la recién liquidada y la omite en la siguiente operación',
    () {
      AccountEntry movement(String id, int amount, int time, bool payment) =>
          AccountEntry(
            id: id,
            eventId: id,
            amountMinor: amount,
            occurredAtMs: time,
            isPayment: payment,
            deliveryStatus: 'not_required',
          );
      final entries = [
        movement('v1', 2000, 1, false),
        movement('a1', 1000, 2, true),
        movement('v2', 5000, 3, false),
        movement('a2', 500, 4, true),
        movement('a3', 1000, 5, true),
      ];
      final account = CustomerAccount(entries);
      final text = CustomerAccountDisplay.statement(
        'Ana',
        account,
        operationId: 'a3',
      );
      expect(text, contains('Folio: v1'));
      expect(text, contains('Liquidada en esta operación'));
      expect(text, contains(r'Pendiente: $45.00'));
      final next = CustomerAccount([...entries, movement('a4', 100, 6, true)]);
      final nextText = CustomerAccountDisplay.statement(
        'Ana',
        next,
        operationId: 'a4',
      );
      expect(nextText, isNot(contains('Folio: v1')));
      expect(nextText, contains('Folio: v2'));
    },
  );
}
