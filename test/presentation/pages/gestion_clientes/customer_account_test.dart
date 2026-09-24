import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/creditos/credito_command_service.dart';
import 'package:pos_flutter/application/commands/creditos/registrar_abono_command.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/clientes/cliente.dart';
import 'package:pos_flutter/domain/creditos/account_entry.dart';
import 'package:pos_flutter/domain/creditos/customer_account.dart';
import 'package:pos_flutter/domain/repositories/cliente_repository.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/repositories/customer_account_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_account_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/customer_statement_image_generator.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/customer_statement_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/models/customer_statement_display.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/registrar_abono_screen.dart';
import 'package:share_plus/share_plus.dart';

import '../../../support/pump_receipt_image.dart';

class _Clientes implements ClienteRepository {
  @override
  Stream<List<Cliente>> watchClientes() => Stream.value([cliente]);
}

class _Account implements CustomerAccountRepository {
  _Account();
  static const _movements = [
    AccountEntry(
      id: 'v1',
      eventId: 'e1',
      amountMinor: 2000,
      occurredAtMs: 1000,
      isPayment: false,
      deliveryStatus: 'not_required',
    ),
    AccountEntry(
      id: 'a1',
      eventId: 'e2',
      amountMinor: 1000,
      occurredAtMs: 2000,
      isPayment: true,
      deliveryStatus: 'pending',
      method: 'cash',
    ),
  ];
  @override
  Stream<CustomerAccount> watchAccount(String clienteId) =>
      Stream.value(CustomerAccount(_movements));
}

class _Sales implements ConfirmedSaleRepository {
  _Sales(this.sales);
  final List<ConfirmedSale> sales;
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value(sales);
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

AccountEntry movement(String id, int amount, int time, bool payment) =>
    AccountEntry(
      id: id,
      eventId: id,
      amountMinor: amount,
      occurredAtMs: time,
      isPayment: payment,
      deliveryStatus: 'not_required',
    );

ConfirmedSale creditSale(
  String id,
  DateTime createdAt,
  List<SaleDraftItem> items,
) {
  final total = items.fold(0, (sum, item) => sum + item.totalMinor);
  return ConfirmedSale(
    id: id,
    createdAt: createdAt,
    totalMinor: total,
    receivedMinor: 0,
    changeMinor: 0,
    currency: 'MXN',
    paymentMethod: 'credit',
    deliveryStatus: 'not_required',
    reason: null,
    clienteId: 'ana',
    clienteNombre: 'Ana',
    items: items,
  );
}

void main() {
  testWidgets('genera el comprobante completo como PNG', (tester) async {
    final account = await _Account().watchAccount('ana').first;
    final statement = CustomerStatement.build(
      clienteNombre: 'Ana',
      businessName: 'Miradent',
      account: account,
      sales: const [],
    );
    final bytes = await tester.runAsync(
      () => CustomerStatementImageGenerator().generate(statement),
    );
    expect(bytes!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(bytes.length, greaterThan(1000));
  });

  testWidgets('muestra saldo, historial, detalle y abre el estado de cuenta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClienteAccountScreen(
          cliente: cliente,
          repository: _Account(),
          clienteRepository: _Clientes(),
          salesRepository: _Sales(const []),
          businessName: 'Miradent',
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
    await pumpReceiptImage(tester);
    expect(find.byType(CustomerStatementScreen), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerStatementScreen), findsNothing);
    expect(find.byType(ClienteAccountScreen), findsOneWidget);
  });

  testWidgets('tras guardar un abono abre el comprobante de ese abono', (
    tester,
  ) async {
    final service = _Service();
    await getIt.reset();
    getIt.registerSingleton<CreditoCommandService>(service);
    addTearDown(() => getIt.reset());
    await tester.pumpWidget(
      MaterialApp(
        home: ClienteAccountScreen(
          cliente: cliente,
          repository: _Account(),
          clienteRepository: _Clientes(),
          salesRepository: _Sales(const []),
          businessName: 'Miradent',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar abono'));
    await tester.pumpAndSettle();
    expect(service.commands, isEmpty);
    await tester.enterText(find.byKey(const Key('abono_importe')), '10.00');
    await tester.tap(find.text('Guardar abono'));
    await tester.pump();
    service.result.complete('a1');
    await pumpReceiptImage(tester);
    expect(find.byType(CustomerStatementScreen), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
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

  testWidgets('comparte la misma imagen que se muestra en la vista previa', (
    tester,
  ) async {
    final pending = Completer<ShareResult>();
    final requests = <ShareParams>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerStatementScreen(
          clienteId: 'ana',
          clienteNombre: 'Ana',
          repository: _Account(),
          salesRepository: _Sales(const []),
          businessName: 'Miradent',
          shareReceipt: (params) {
            requests.add(params);
            return pending.future;
          },
        ),
      ),
    );
    await pumpReceiptImage(tester);
    final preview =
        tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    await tester.tap(find.text('Compartir'));
    await tester.pump();
    expect(requests, hasLength(1));
    final params = requests.single;
    expect(params.files, hasLength(1));
    expect(params.files!.single.mimeType, 'image/png');
    expect(await params.files!.single.readAsBytes(), preview.bytes);
    expect(params.fileNameOverrides, ['estado-cuenta.png']);
    expect(params.title, 'Cuenta de Ana');
    expect(params.downloadFallbackEnabled, isFalse);
    final button = find.widgetWithText(FilledButton, 'Compartir');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    pending.complete(const ShareResult('', ShareResultStatus.dismissed));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  test(
    'comprobante tras un abono separa pendientes, liquidados y totales',
    () {
      // Aceptación: dos compras de $500 y $1,000, $300 abonados al primero y
      // otro abono de $500.
      final account = CustomerAccount([
        movement('v1', 50000, 1, false),
        movement('v2', 100000, 2, false),
        movement('a1', 30000, 3, true),
        movement('a2', 50000, 4, true),
      ]);
      final statement = CustomerStatement.build(
        clienteNombre: 'Ana',
        businessName: 'Miradent',
        account: account,
        sales: const [],
        operationId: 'a2',
      );
      expect(statement.pendingReceipts.map((r) => r.folio), ['v2']);
      expect(statement.liquidatedReceipts.map((r) => r.folio), ['v1']);
      expect(statement.totalComprasMinor, 150000);
      expect(statement.totalAbonadoMinor, 80000);
      expect(statement.saldoPendienteMinor, 70000);
      expect(
        statement.payments.map((p) => p.appliedMinor),
        [30000, 50000],
      );
      expect(statement.isOperacionReciente, isTrue);
    },
  );

  test('la consulta general posterior no arrastra recibos liquidados', () {
    final account = CustomerAccount([
      movement('v1', 50000, 1, false),
      movement('v2', 100000, 2, false),
      movement('a1', 30000, 3, true),
      movement('a2', 50000, 4, true),
    ]);
    final statement = CustomerStatement.build(
      clienteNombre: 'Ana',
      account: account,
      sales: const [],
    );
    expect(statement.pendingReceipts.map((r) => r.folio), ['v2']);
    expect(statement.liquidatedReceipts, isEmpty);
    expect(statement.totalComprasMinor, 100000);
    // Solo se muestran los $300 del segundo abono aplicados al crédito vigente.
    expect(statement.payments.map((p) => p.appliedMinor), [30000]);
    expect(statement.totalAbonadoMinor, 30000);
    expect(statement.saldoPendienteMinor, 70000);
    expect(statement.isOperacionReciente, isFalse);
  });

  test('un pago aplicado a varios recibos aparece una sola vez', () {
    // p1 liquida v1 y deja v2 pendiente: ambos entran en el comprobante de
    // esa operación, pero el pago se muestra una sola vez.
    final account = CustomerAccount([
      movement('v1', 10000, 1, false),
      movement('v2', 20000, 2, false),
      movement('p1', 25000, 3, true),
    ]);
    final statement = CustomerStatement.build(
      clienteNombre: 'Ana',
      account: account,
      sales: const [],
      operationId: 'p1',
    );
    expect(statement.liquidatedReceipts.map((r) => r.folio), ['v1']);
    expect(statement.pendingReceipts.map((r) => r.folio), ['v2']);
    expect(statement.payments, hasLength(1));
    expect(statement.payments.single.appliedMinor, 25000);
    expect(statement.totalComprasMinor, 30000);
    expect(statement.totalAbonadoMinor, 25000);
    expect(statement.saldoPendienteMinor, 5000);
  });

  test('no suma lo aplicado a créditos fuera del comprobante', () {
    // p1 liquida v1 y solo deja $20 aplicados al recibo v2 del comprobante.
    final account = CustomerAccount([
      movement('v1', 10000, 1, false),
      movement('v2', 5000, 2, false),
      movement('p1', 12000, 3, true),
    ]);
    final statement = CustomerStatement.build(
      clienteNombre: 'Ana',
      account: account,
      sales: const [],
    );
    expect(statement.pendingReceipts.map((r) => r.folio), ['v2']);
    expect(statement.payments.map((p) => p.appliedMinor), [2000]);
    expect(statement.totalAbonadoMinor, 2000);
    expect(statement.saldoPendienteMinor, 3000);
  });

  test('el excedente a favor se muestra aparte sin descontarse dos veces', () {
    final account = CustomerAccount([
      movement('v1', 10000, 1, false),
      movement('p1', 15000, 2, true),
    ]);
    final statement = CustomerStatement.build(
      clienteNombre: 'Ana',
      account: account,
      sales: const [],
    );
    expect(statement.pendingReceipts, isEmpty);
    expect(statement.payments, isEmpty);
    expect(statement.saldoPendienteMinor, 0);
    expect(statement.saldoFavorMinor, BigInt.from(5000));
  });

  test('recupera el detalle comercial del recibo de venta original', () {
    final sale = creditSale('v1', DateTime(2026, 9, 16, 20, 12), const [
      SaleDraftItem(
        id: 'l1',
        variantId: 'a',
        productName: 'Lentes de contacto',
        variantName: null,
        quantity: 2,
        measuredQuantityAtomic: null,
        unitPriceMinor: 5000,
        priceReferenceQuantityAtomic: null,
        unitCode: null,
        unitSymbol: null,
        unitAtomicFactor: null,
        totalMinor: 10000,
      ),
      SaleDraftItem(
        id: 'l2',
        variantId: 'b',
        productName: 'Solución',
        variantName: null,
        quantity: 1,
        measuredQuantityAtomic: null,
        unitPriceMinor: 1100,
        priceReferenceQuantityAtomic: null,
        unitCode: null,
        unitSymbol: null,
        unitAtomicFactor: null,
        totalMinor: 1100,
      ),
    ]);
    final account = CustomerAccount([movement('v1', 11100, 1, false)]);
    final statement = CustomerStatement.build(
      clienteNombre: 'Ana',
      account: account,
      sales: [sale],
    );
    final receipt = statement.pendingReceipts.single;
    expect(receipt.folio, 'v1');
    expect(receipt.date, '16/09/2026 20:12');
    expect(receipt.itemRows, [
      ['Lentes de contacto', r'$50.00', '2', r'$100.00'],
      ['Solución', r'$11.00', '1', r'$11.00'],
    ]);
    expect(receipt.totalMinor, 11100);
  });

  test('formatea importes con separadores de miles y dos decimales', () {
    expect(CustomerStatement.money(152500), r'$1,525.00');
    expect(CustomerStatement.money(0), r'$0.00');
    expect(CustomerStatement.money(-500), r'-$5.00');
    expect(CustomerStatement.date(DateTime(2026, 9, 24, 10, 30)), '24/09/2026 10:30');
  });
}