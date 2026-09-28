import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/transfer_summary_repository_impl.dart';
import 'package:pos_flutter/domain/finanzas/transfer_summary.dart';

/// 2026-09-10T12:00:00Z como base del periodo de las pruebas.
final _base = DateTime.utc(2026, 9, 10, 12);
int _ms(int hours) => _base.add(Duration(hours: hours)).millisecondsSinceEpoch;

void main() {
  late AppDatabase db;
  late TransferSummaryRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TransferSummaryRepositoryImpl(db);
  });
  tearDown(() => db.close());

  Future<void> evento(
    String eventId, {
    String applicationStatus = 'applied',
    String deliveryStatus = 'delivered',
    DateTime? createdAtLocal,
  }) => db.into(db.events).insert(
    EventsCompanion.insert(
      eventId: eventId,
      aggregateType: 'test',
      aggregateId: eventId,
      eventType: 'test',
      deviceId: 'tablet',
      userId: 'user',
      createdAtLocal: createdAtLocal ?? _base,
      payload: '{}',
      applicationStatus: Value(applicationStatus),
      deliveryStatus: Value(deliveryStatus),
    ),
  );

  Future<void> cliente(String id, String nombre) => db
      .into(db.clientes)
      .insert(
        ClientesCompanion.insert(id: id, nombre: nombre),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> venta(String id, {String? clienteId}) async {
    if (clienteId != null) await cliente(clienteId, 'Ana');
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: id,
        userId: 'user',
        deviceId: 'tablet',
        totalMinor: 1000,
        status: const Value('confirmada'),
        createdAtLocal: _base,
        updatedAtLocal: _base,
        clienteId: Value(clienteId),
      ),
    );
  }

  /// Pago de venta. `sale_payments` no tiene occurred_at_ms (H1b): la fecha
  /// efectiva sale de `events.created_at_local` del evento que lo creó.
  Future<void> pagoVenta(
    String id, {
    required String eventId,
    required String saleId,
    required int amountMinor,
    required String method,
    DateTime? createdAtLocal,
  }) async {
    await venta(saleId, clienteId: 'a');
    await evento(eventId, createdAtLocal: createdAtLocal);
    await db.into(db.salePayments).insert(
      SalePaymentsCompanion.insert(
        id: id,
        saleId: saleId,
        amountMinor: amountMinor,
        method: Value(method),
        receivedMinor: amountMinor,
        changeMinor: 0,
        currency: 'MXN',
        createdEventId: Value(eventId),
      ),
    );
  }

  Future<void> abono(
    String id, {
    required String eventId,
    required int amountMinor,
    required String method,
    required int occurredAtMs,
    String? reference,
  }) async {
    await cliente('a', 'Ana');
    await evento(eventId);
    await db.into(db.customerPayments).insert(
      CustomerPaymentsCompanion.insert(
        id: id,
        clienteId: 'a',
        amountMinor: amountMinor,
        method: method,
        occurredAtMs: occurredAtMs,
        reference: Value(reference),
        createdEventId: Value(eventId),
      ),
    );
  }

  Future<void> movimientoFinanciero(
    String id, {
    required String eventId,
    required int amountMinor,
    required String direction,
    required String method,
    required int occurredAtMs,
    String nature = 'operating',
    String applicationStatus = 'applied',
  }) async {
    await evento(eventId, applicationStatus: applicationStatus);
    await db.into(db.financialCategories).insert(
      FinancialCategoriesCompanion.insert(
        id: 'cat-$id',
        name: 'Categoría $nature',
        direction: nature == 'asset_purchase' ? 'out' : direction,
        nature: nature,
      ),
    );
    await db.into(db.financialEntries).insert(
      FinancialEntriesCompanion.insert(
        id: id,
        categoryId: 'cat-$id',
        categoryNameSnapshot: 'Categoría $nature',
        direction: direction,
        nature: nature,
        amountMinor: amountMinor,
        currency: 'MXN',
        method: method,
        occurredAtMs: occurredAtMs,
        createdEventId: Value(eventId),
      ),
    );
  }

  Future<TransferSummary> resumen({int? fromMs, int? toMs}) => repository
      .watchTransferSummary(
        fromMs: fromMs ?? _ms(0),
        toMs: toMs ?? _ms(24),
      )
      .first;

  test('los tres origenes entran con su signo y el neto es la resta', () async {
    await pagoVenta(
      'sp1',
      eventId: 'ev-sp1',
      saleId: 's1',
      amountMinor: 5000,
      method: 'transfer',
    );
    await abono(
      'cp1',
      eventId: 'ev-cp1',
      amountMinor: 3000,
      method: 'transfer',
      occurredAtMs: _ms(1),
    );
    await movimientoFinanciero(
      'fe1',
      eventId: 'ev-fe1',
      amountMinor: 7000,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(2),
    );
    await movimientoFinanciero(
      'fe2',
      eventId: 'ev-fe2',
      amountMinor: 2500,
      direction: 'out',
      method: 'transfer',
      occurredAtMs: _ms(3),
    );

    final summary = await resumen();

    expect(summary.movements, hasLength(4));
    expect(
      summary.byOrigin[TransferOrigin.sale],
      BigInt.from(5000),
      reason: 'una venta por transferencia solo puede entrar',
    );
    expect(summary.byOrigin[TransferOrigin.customerPayment], BigInt.from(3000));
    expect(
      summary.byOrigin[TransferOrigin.financialEntry],
      BigInt.from(4500),
      reason: 'in suma y out resta dentro del mismo origen',
    );
    expect(summary.incomeMinor, BigInt.from(15000));
    expect(summary.expenseMinor, BigInt.from(2500));
    expect(summary.netMinor, BigInt.from(12500));
  });

  test('cada movimiento trae su importe positivo y su importe con signo', () async {
    await movimientoFinanciero(
      'fe1',
      eventId: 'ev-fe1',
      amountMinor: 7000,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(2),
    );
    await movimientoFinanciero(
      'fe2',
      eventId: 'ev-fe2',
      amountMinor: 2500,
      direction: 'out',
      method: 'transfer',
      occurredAtMs: _ms(3),
    );

    final summary = await resumen();
    final salida = summary.movements.singleWhere((m) => m.id == 'fe2');

    expect(salida.amountMinor, 2500);
    expect(salida.signedAmountMinor, BigInt.from(-2500));
    expect(salida.origin, TransferOrigin.financialEntry);
    expect(salida.occurredAtMs, _ms(3));
  });

  test('los totales son BigInt y no pierden precisión sobre 2^53', () async {
    final grande = 4000000000000000; // 4e15
    for (var i = 0; i < 3; i++) {
      await movimientoFinanciero(
        'fe$i',
        eventId: 'ev-fe$i',
        amountMinor: grande,
        direction: 'in',
        method: 'transfer',
        occurredAtMs: _ms(i),
      );
    }

    final summary = await resumen();

    expect(summary.incomeMinor, isA<BigInt>());
    expect(summary.netMinor, isA<BigInt>());
    expect(summary.incomeMinor, BigInt.from(12000000000000000));
  });

  test('el efectivo de los tres origenes no cuenta como transferencia', () async {
    await pagoVenta(
      'sp1',
      eventId: 'ev-sp1',
      saleId: 's1',
      amountMinor: 5000,
      method: 'cash',
    );
    await abono(
      'cp1',
      eventId: 'ev-cp1',
      amountMinor: 3000,
      method: 'cash',
      occurredAtMs: _ms(1),
    );
    await movimientoFinanciero(
      'fe1',
      eventId: 'ev-fe1',
      amountMinor: 7000,
      direction: 'in',
      method: 'cash',
      occurredAtMs: _ms(2),
    );
    await movimientoFinanciero(
      'fe2',
      eventId: 'ev-fe2',
      amountMinor: 1000,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(3),
    );

    final summary = await resumen();

    expect(summary.movements.map((m) => m.id), ['fe2']);
    expect(summary.incomeMinor, BigInt.from(1000));
  });

  test('el periodo es [from, to): incluye el inicio y excluye el fin', () async {
    await movimientoFinanciero(
      'fe-inicio',
      eventId: 'ev-a',
      amountMinor: 1000,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(0),
    );
    await movimientoFinanciero(
      'fe-medio',
      eventId: 'ev-b',
      amountMinor: 2000,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(1),
    );
    await movimientoFinanciero(
      'fe-fin',
      eventId: 'ev-c',
      amountMinor: 4000,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(2),
    );

    final summary = await resumen(fromMs: _ms(0), toMs: _ms(2));

    expect(
      summary.movements.map((m) => m.id),
      ['fe-medio', 'fe-inicio'],
      reason: 'desde el inicio included, hasta el fin exclusive',
    );
    expect(summary.incomeMinor, BigInt.from(3000));
  });

  test('la venta por transferencia se fecha con su evento, no con el borrador', () async {
    await venta('s1', clienteId: 'a');
    await evento('ev-sp1', createdAtLocal: _base.add(const Duration(hours: 5)));
    await db.into(db.salePayments).insert(
      SalePaymentsCompanion.insert(
        id: 'sp1',
        saleId: 's1',
        amountMinor: 5000,
        method: const Value('transfer'),
        receivedMinor: 5000,
        changeMinor: 0,
        currency: 'MXN',
        createdEventId: const Value('ev-sp1'),
      ),
    );

    final dentroDelPeriodoTardio = await resumen(
      fromMs: _ms(4),
      toMs: _ms(6),
    );
    expect(dentroDelPeriodoTardio.incomeMinor, BigInt.from(5000));

    final antesDelCobro = await resumen(fromMs: _ms(0), toMs: _ms(4));
    expect(antesDelCobro.movements, isEmpty);
    expect(antesDelCobro.incomeMinor, BigInt.zero);
  });

  test('lo no aplicado localmente no suma, y lo pendiente sí', () async {
    await movimientoFinanciero(
      'fe-fallido',
      eventId: 'ev-a',
      amountMinor: 9000,
      direction: 'out',
      method: 'transfer',
      occurredAtMs: _ms(1),
      applicationStatus: 'failed',
    );
    await movimientoFinanciero(
      'fe-pendiente',
      eventId: 'ev-b',
      amountMinor: 1200,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(2),
    );
    await db.into(db.events).insert(
      EventsCompanion.insert(
        eventId: 'ev-c',
        aggregateType: 'test',
        aggregateId: 'fe-pendiente-envio',
        eventType: 'test',
        deviceId: 'tablet',
        userId: 'user',
        createdAtLocal: _base,
        payload: '{}',
        deliveryStatus: const Value('pending'),
      ),
    );
    await db.into(db.financialEntries).insert(
      FinancialEntriesCompanion.insert(
        id: 'fe-no-sincronizado',
        categoryId: 'cat-fe-pendiente',
        categoryNameSnapshot: 'Categoría operating',
        direction: 'in',
        nature: 'operating',
        amountMinor: 800,
        currency: 'MXN',
        method: 'transfer',
        occurredAtMs: _ms(3),
        createdEventId: const Value('ev-c'),
      ),
    );

    final summary = await resumen();

    expect(
      summary.movements.map((m) => m.id),
      containsAll(['fe-pendiente', 'fe-no-sincronizado']),
    );
    expect(
      summary.movements.map((m) => m.id),
      isNot(contains('fe-fallido')),
      reason: 'un evento fallido nunca se aplicó, no es dinero que se movió',
    );
    expect(summary.incomeMinor, BigInt.from(2000));
    expect(summary.expenseMinor, BigInt.zero);
  });

  test('repartir un abono de crédito no suma dinero otra vez', () async {
    await venta('s1', clienteId: 'a');
    await cliente('a', 'Ana');
    await db.into(db.creditSales).insert(
      CreditSalesCompanion.insert(
        id: 's1',
        saleId: 's1',
        clienteId: 'a',
        amountMinor: 5000,
        occurredAtMs: _ms(0),
      ),
    );
    await abono(
      'cp1',
      eventId: 'ev-cp1',
      amountMinor: 5000,
      method: 'transfer',
      occurredAtMs: _ms(1),
    );
    await db.into(db.creditAllocations).insert(
      CreditAllocationsCompanion.insert(
        paymentId: 'cp1',
        creditId: 's1',
        amountMinor: 5000,
      ),
    );

    final summary = await resumen();

    expect(
      summary.movements.map((m) => m.id),
      ['cp1'],
      reason: 'credit_allocations es proyección FIFO, no un movimiento de dinero',
    );
    expect(summary.incomeMinor, BigInt.from(5000));
  });

  test('un periodo sin transferencias aggregate en ceros', () async {
    await movimientoFinanciero(
      'fe1',
      eventId: 'ev-fe1',
      amountMinor: 7000,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(1),
    );

    final summary = await resumen(fromMs: _ms(48), toMs: _ms(72));

    expect(summary.isEmpty, isTrue);
    expect(summary.incomeMinor, BigInt.zero);
    expect(summary.expenseMinor, BigInt.zero);
    expect(summary.netMinor, BigInt.zero);
    expect(summary.byOrigin, isEmpty);
  });

  test('un movimiento de capital también cuenta, sin filtro de naturaleza', () async {
    await movimientoFinanciero(
      'fe-capital',
      eventId: 'ev-capital',
      amountMinor: 1500,
      direction: 'out',
      method: 'transfer',
      occurredAtMs: _ms(1),
      nature: 'capital',
    );

    final summary = await resumen();

    expect(summary.expenseMinor, BigInt.from(1500));
    expect(summary.netMinor, BigInt.from(-1500));
  });

  test('el agregado se actualiza en vivo sin perder el BigInt', () async {
    await movimientoFinanciero(
      'fe1',
      eventId: 'ev-fe1',
      amountMinor: 1000,
      direction: 'in',
      method: 'transfer',
      occurredAtMs: _ms(1),
    );
    final stream = repository.watchTransferSummary(fromMs: _ms(0), toMs: _ms(24));
    expect((await stream.first).incomeMinor, BigInt.from(1000));

    await movimientoFinanciero(
      'fe2',
      eventId: 'ev-fe2',
      amountMinor: 2000,
      direction: 'out',
      method: 'transfer',
      occurredAtMs: _ms(2),
    );

    final actualizado = await stream.firstWhere(
      (summary) => summary.netMinor == BigInt.from(-1000),
    );
    expect(actualizado.incomeMinor, BigInt.from(1000));
    expect(actualizado.expenseMinor, BigInt.from(2000));
  });
}
