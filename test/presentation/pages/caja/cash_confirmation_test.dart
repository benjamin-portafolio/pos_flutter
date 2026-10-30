import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/clientes/cliente.dart';
import 'package:pos_flutter/domain/repositories/cliente_repository.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';
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

class _Clients implements ClienteRepository {
  @override
  Stream<List<Cliente>> watchClientes() =>
      Stream.value(const [Cliente(id: 'ana', nombre: 'Ana', telefono: '555')]);
}

void main() {
  setUp(() => getIt.registerSingleton<ConfirmedSaleRepository>(_Repository()));
  tearDown(() => getIt.unregister<ConfirmedSaleRepository>());
  for (final input in ['', '100', '200']) {
    testWidgets('confirma $input después de commit y bloquea doble toque', (
      tester,
    ) async {
      final service = _Service();
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => PaymentMethodScreen(
                        totalMinor: 10000,
                        saleId: 'sale',
                        expectedDraftEventId: 'draft-revision',
                        commandService: service,
                      ),
                    ),
                  );
                },
                child: const Text('Caja de prueba'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Caja de prueba'));
      await tester.pumpAndSettle();
      if (input.isNotEmpty) {
        await tester.enterText(
          find.byKey(const Key('cash_received_input')),
          input,
        );
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
      await tester.pumpAndSettle();
      expect(find.byType(SaleReceiptScreen), findsNothing);
      expect(find.byType(PaymentMethodScreen), findsNothing);
      expect(find.text('Caja de prueba'), findsOneWidget);
      expect(result, isTrue);
    });
  }
  for (final method in ['cash', 'transfer', 'credit']) {
    testWidgets('$method guarda y regresa a Caja con el recorrido esperado', (
      tester,
    ) async {
      final service = _Service();
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => PaymentMethodScreen(
                        totalMinor: 10000,
                        saleId: 'sale',
                        expectedDraftEventId: 'draft',
                        commandService: service,
                        clienteRepository: _Clients(),
                      ),
                    ),
                  );
                },
                child: const Text('Caja de prueba'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Caja de prueba'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Buscar cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cash_received_input')),
        '200',
      );
      await tester.tap(find.byKey(const Key('payment_tab_transfer')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('transfer_reference_input')),
        'Banco',
      );
      await tester.tap(find.byKey(Key('payment_tab_$method')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(switch (method) {
          'cash' => 'Recibido por efectivo',
          'transfer' => 'Confirmar transferencia',
          _ => 'Confirmar crédito',
        }),
      );
      await tester.pumpAndSettle();
      if (method == 'credit') {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Confirmar crédito'),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(service.commands, hasLength(1));
      final command = service.commands.single;
      expect(command.paymentMethod, method);
      expect(command.clienteId, 'ana');
      expect(command.receivedMinor, method == 'cash' ? 20000 : null);
      expect(command.paymentReference, method == 'transfer' ? 'Banco' : null);
      expect(find.byType(SaleReceiptScreen), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodScreen), findsOneWidget);
      service.commit.complete('confirmed');
      if (method == 'cash') {
        await tester.pumpAndSettle();
        expect(find.byType(SaleReceiptScreen), findsNothing);
      } else {
        await pumpReceiptImage(tester);
        expect(find.byType(SaleReceiptScreen), findsOneWidget);
        await tester.tap(find.text('Nueva venta'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodScreen), findsNothing);
      expect(find.text('Caja de prueba'), findsOneWidget);
      expect(result, isTrue);
    });
  }
  testWidgets(
    'insuficiente no confirma; fallo conserva captura para revisión',
    (tester) async {
      final service = _Service();
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentMethodScreen(
            totalMinor: 10000,
            saleId: 'sale',
            expectedDraftEventId: 'draft',
            commandService: service,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('cash_received_input')),
        '99',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Recibido por efectivo'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('cash_received_input')),
        '200',
      );
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
