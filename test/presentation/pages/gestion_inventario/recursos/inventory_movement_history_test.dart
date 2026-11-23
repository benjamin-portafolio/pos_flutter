import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/movimiento_inventario.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/repositories/recurso_inventario_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/recursos/widgets/inventory_movement_history.dart';

const _unit = UnidadInventario(
  id: 'kg',
  code: 'kg',
  nombre: 'Kilogramo',
  simbolo: 'kg',
  dimension: DimensionUnidad.mass,
  factorAtomico: 1000,
  maximosDecimales: 3,
  activa: true,
);

MovimientoInventario _movement(int i, {String? reason}) => MovimientoInventario(
  id: '$i',
  inventoryItemId: 'flour',
  saleId: i == 0 ? 'venta-123' : null,
  saleItemId: i == 0 ? 'line-1' : null,
  eventId: 'event-$i',
  reversalOfMovementId: i == 1 ? 'original-123' : null,
  movementType: i == 0 ? 'sale_consumption' : 'stock_receipt',
  quantityDeltaAtomic: i == 0 ? -500 : 1000,
  totalCostMinor: i == 0 ? null : 2500,
  reason: reason ?? (i == 1 ? 'Compra de mercancía' : null),
  createdAtLocal: DateTime(2026, 11, 20, 10, 45),
  serverSequence: null,
);

Widget _view(_Repository repository) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: InventoryMovementHistory(
        repository: repository,
        inventoryItemId: 'flour',
        unit: _unit,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'tarjetas muestran cantidades, costo, motivo y origen; carga más y filtra',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(_view(repository));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('−0.5 kg'), findsOneWidget);
      expect(find.text('Venta: venta-123'), findsOneWidget);
      expect(find.text('Compensa movimiento: original-123'), findsOneWidget);
      expect(find.text('Sin costo registrado'), findsOneWidget);
      expect(find.text('Costo total: \$25.00'), findsNWidgets(19));
      expect(find.text('Compra de mercancía'), findsOneWidget);
      expect(find.text('20/11/2026 10:45'), findsNWidgets(20));
      await tester.ensureVisible(find.text('Cargar más'));
      await tester.tap(find.text('Cargar más'));
      await tester.pumpAndSettle();
      expect(repository.requestedLimit, 41);
      expect(find.text('Cargar más'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('inventory_history_type')),
      );
      await tester.tap(find.byKey(const Key('inventory_history_type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consumo por venta').last);
      await tester.pumpAndSettle();
      expect(repository.requestedType, 'sale_consumption');
      expect(repository.requestedLimit, 21);
      expect(find.text('−0.5 kg'), findsOneWidget);
      expect(find.text('+1 kg'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tabla de escritorio admite motivos largos sin desbordarse', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Repository()
      ..stream = Stream.value([
        _movement(1, reason: List.filled(50, 'Motivo largo').join(' ')),
      ]);
    await tester.pumpWidget(_view(repository));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Cantidad'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('periodo incluye el día final; quitar filtro restaura todos', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(_view(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory_history_period')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '01/02/2025');
    await tester.enterText(fields.at(1), '01/03/2025');
    await tester.tap(find.text('APLICAR'));
    await tester.pumpAndSettle();
    expect(repository.desde, DateTime(2025, 1, 2));
    expect(repository.hasta, DateTime(2025, 1, 4));
    await tester.tap(find.byTooltip('Quitar filtro de periodo'));
    await tester.pumpAndSettle();
    expect(repository.desde, isNull);
    expect(repository.hasta, isNull);
  });

  testWidgets('muestra carga, vacío y error con reintento', (tester) async {
    final repository = _Repository();
    final controller = StreamController<List<MovimientoInventario>>();
    repository.stream = controller.stream;
    await tester.pumpWidget(_view(repository));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    controller.add(const []);
    await tester.pumpAndSettle();
    expect(
      find.text('No hay movimientos para los filtros seleccionados.'),
      findsOneWidget,
    );
    controller.addError(StateError('fallo local'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar el historial.'), findsOneWidget);
    repository.stream = Stream.value([_movement(0)]);
    await tester.tap(find.text('REINTENTAR'));
    await tester.pumpAndSettle();
    expect(find.text('Venta: venta-123'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    addTearDown(controller.close);
  });
}

class _Repository implements RecursoInventarioRepository {
  int? requestedLimit;
  String? requestedType;
  DateTime? desde;
  DateTime? hasta;
  Stream<List<MovimientoInventario>>? stream;

  @override
  Stream<List<MovimientoInventario>> watchMovimientos(
    String inventoryItemId, {
    String? movementType,
    DateTime? desde,
    DateTime? hasta,
    int limit = 20,
  }) {
    requestedLimit = limit;
    requestedType = movementType;
    this.desde = desde;
    this.hasta = hasta;
    return stream ??
        Stream.value(
          List.generate(25, _movement)
              .where(
                (movement) =>
                    movementType == null ||
                    movement.movementType == movementType,
              )
              .take(limit)
              .toList(),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
