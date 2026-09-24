import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/widgets/cliente_compras_section.dart';

import '../../../support/pump_receipt_image.dart';

class _Sales implements ConfirmedSaleRepository {
  _Sales(this.sales);
  final List<ConfirmedSale> sales;
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value(sales);
}

class _FlakySales implements ConfirmedSaleRepository {
  _FlakySales(this.sales);
  final List<ConfirmedSale> sales;
  bool fail = true;
  @override
  Stream<List<ConfirmedSale>> watchSales() =>
      fail ? Stream.error(StateError('fallo')) : Stream.value(sales);
}

ConfirmedSale saleOf({
  required String id,
  required DateTime createdAt,
  String clienteId = 'ana',
  String? clienteNombre = 'Ana',
  String paymentMethod = 'credit',
  int total = 2500,
  int articles = 1,
}) {
  final items = [
    for (var i = 0; i < articles; i++)
      SaleDraftItem(
        id: 'l-$id-$i',
        variantId: 'v-$id-$i',
        productName: 'Producto $i',
        variantName: null,
        quantity: 1,
        measuredQuantityAtomic: null,
        unitPriceMinor: total,
        priceReferenceQuantityAtomic: null,
        unitCode: null,
        unitSymbol: null,
        unitAtomicFactor: null,
        totalMinor: total,
      ),
  ];
  return ConfirmedSale(
    id: id,
    clienteId: clienteId,
    clienteNombre: clienteNombre,
    paymentMethod: paymentMethod,
    createdAt: createdAt,
    totalMinor: items.fold(0, (sum, item) => sum + item.totalMinor),
    receivedMinor: 0,
    changeMinor: 0,
    currency: 'MXN',
    deliveryStatus: 'not_required',
    reason: null,
    items: items,
  );
}

Future<void> pumpSection(
  WidgetTester tester,
  ConfirmedSaleRepository repository, {
  String clienteId = 'ana',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClienteComprasSection(
            clienteId: clienteId,
            repository: repository,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'filtra por cliente, ordena de reciente a antiguo y muestra el total real',
    (tester) async {
      final sales = [
        saleOf(id: 'v1', createdAt: DateTime(2026, 1, 1), clienteId: 'otro'),
        saleOf(id: 'v2', createdAt: DateTime(2026, 1, 3)),
        saleOf(id: 'v3', createdAt: DateTime(2026, 1, 2)),
        saleOf(id: 'v4', createdAt: DateTime(2026, 1, 5)),
        saleOf(id: 'v5', createdAt: DateTime(2026, 1, 4)),
        saleOf(id: 'v6', createdAt: DateTime(2026, 1, 6)),
        saleOf(id: 'v7', createdAt: DateTime(2026, 1, 7)),
        saleOf(id: 'v8', createdAt: DateTime(2026, 1, 8)),
      ];
      await pumpSection(tester, _Sales(sales));

      // El título usa el total real, no las tarjetas cargadas.
      expect(find.text('Compras (7)'), findsOneWidget);
      expect(find.byKey(const ValueKey('cliente_compra_v1')), findsNothing);
      // Primer grupo: las 5 más recientes, empezando por la más nueva.
      expect(find.byKey(const ValueKey('cliente_compra_v8')), findsOneWidget);
      expect(find.byKey(const ValueKey('cliente_compra_v7')), findsOneWidget);
      expect(find.byKey(const ValueKey('cliente_compra_v6')), findsOneWidget);
      expect(find.byKey(const ValueKey('cliente_compra_v5')), findsOneWidget);
      expect(find.byKey(const ValueKey('cliente_compra_v4')), findsOneWidget);
      expect(find.byKey(const ValueKey('cliente_compra_v3')), findsNothing);
      expect(find.text('Cargar más'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('cliente_compra_v8'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('cliente_compra_v4'))).dy,
        ),
      );
      // Composición de la tarjeta: cliente · forma de pago y artículos.
      expect(find.text('Ana por Crédito'), findsWidgets);
      expect(find.textContaining('1 artículo ·'), findsWidgets);
      // El id de la compra no se muestra.
      expect(find.text('v8'), findsNothing);
    },
  );

  testWidgets('Cargar más incorpora las siguientes sin reemplazar y se oculta al final', (
    tester,
  ) async {
    await pumpSection(
      tester,
      _Sales([
        for (var i = 1; i <= 8; i++)
          saleOf(id: 'v$i', createdAt: DateTime(2026, 1, i)),
      ]),
    );
    expect(find.text('Compras (8)'), findsOneWidget);
    expect(find.byKey(const ValueKey('cliente_compra_v8')), findsOneWidget);
    expect(find.byKey(const ValueKey('cliente_compra_v4')), findsOneWidget);
    expect(find.byKey(const ValueKey('cliente_compra_v3')), findsNothing);
    expect(find.text('Cargar más'), findsOneWidget);

    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cliente_compra_v8')), findsOneWidget);
    expect(find.byKey(const ValueKey('cliente_compra_v4')), findsOneWidget);
    expect(find.byKey(const ValueKey('cliente_compra_v3')), findsOneWidget);
    expect(find.byKey(const ValueKey('cliente_compra_v1')), findsOneWidget);
    expect(find.text('Cargar más'), findsNothing);
  });

  testWidgets('muestra el estado vacío cuando el cliente no tiene compras', (
    tester,
  ) async {
    await pumpSection(tester, _Sales(const []));
    expect(find.text('Compras (0)'), findsOneWidget);
    expect(find.text('Este cliente aún no tiene compras.'), findsOneWidget);
  });

  testWidgets('la sección se puede contraer y expandir', (tester) async {
    await pumpSection(
      tester,
      _Sales([saleOf(id: 'v1', createdAt: DateTime(2026, 1, 1))]),
    );
    expect(find.byKey(const ValueKey('cliente_compra_v1')), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long), findsOneWidget);

    await tester.tap(find.text('Compras (1)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cliente_compra_v1')), findsNothing);
    expect(find.byIcon(Icons.receipt_long), findsNothing);

    await tester.tap(find.text('Compras (1)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cliente_compra_v1')), findsOneWidget);
  });

  testWidgets('muestra error y permite reintentar la carga', (tester) async {
    final repository = _FlakySales(
      [saleOf(id: 'v1', createdAt: DateTime(2026, 1, 1))],
    );
    await pumpSection(tester, repository);
    expect(find.text('No se pudieron cargar las compras.'), findsOneWidget);

    repository.fail = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Compras (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('cliente_compra_v1')), findsOneWidget);
  });

  testWidgets('al tocar una compra abre el detalle de la venta', (tester) async {
    await pumpSection(
      tester,
      _Sales([saleOf(id: 'v1', createdAt: DateTime(2026, 1, 1))]),
    );
    await tester.tap(find.byKey(const ValueKey('cliente_compra_v1')));
    await pumpReceiptImage(tester);
    expect(find.byType(SaleReceiptScreen), findsOneWidget);
  });
}