import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/data/repositories/cash_repository_impl.dart';

import '../../support/cash_harness.dart';
import '../../support/sale_adjustment_harness.dart';

void main() {
  test('conserva la fecha del evento en caja abierta y en el corte', () async {
    final h = CashHarness();
    addTearDown(h.dispose);
    final id = await h.open();
    final eventId = await h.entry();
    final event = (await h.db.eventDao.obtenerEventoPorId(eventId))!;
    final repository = CashRepositoryImpl(h.db);
    final open = (await repository.watchSessions().first).single;
    expect(open.movements.single.createdAt, event.createdAtLocal);
    expect(open.movements.single.localSequence, event.localSequence);
    expect(open.movements.single.saleId, isNull);

    await h.cash.cerrar(CerrarCajaCommand(sessionId: id, countedMinor: 12500));
    final closed = (await repository.watchSessions().first).single;
    expect(closed.closedMovements!.single.createdAt, event.createdAtLocal);
    expect(closed.closedMovements!.single.localSequence, event.localSequence);
    expect(closed.closedMovements!.single.saleId, isNull);
    expect(closed.expectedMinor, open.expectedMinor);
  });

  test(
    'resuelve la venta del pago tanto en la proyección como en el corte',
    () async {
      final fixture = adjustmentFixtures().firstWhere(
        (f) => object(f['original'])['cash'] != null,
      );
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      await h.seed(fixture);
      final original = object(fixture['original']);
      final sessionId = object(original['cash'])['session_id'];
      final session = (await CashRepositoryImpl(
        h.db,
      ).watchSessions().first).singleWhere((s) => s.id == sessionId);
      final saleId = object(fixture['payload'])['sale_id'];
      expect(session.movements.single.saleId, saleId);
      expect(session.closedMovements!.single.saleId, saleId);
      expect(
        session.closedMovements!.single.createdAt,
        session.movements.single.createdAt,
      );
      expect(session.closedMovements!.single.createdAt, isNotNull);
    },
  );
}
