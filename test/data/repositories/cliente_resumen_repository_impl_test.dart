import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/cliente_resumen_repository_impl.dart';

void main() {
  late AppDatabase db;
  late ClienteResumenRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ClienteResumenRepositoryImpl(db);
  });
  tearDown(() => db.close());

  Future<void> cliente(String id, String nombre) => db
      .into(db.clientes)
      .insert(ClientesCompanion.insert(id: id, nombre: nombre));

  Future<void> venta(
    String id,
    String clienteId, {
    String status = 'confirmada',
    DateTime? updatedAt,
  }) => db.into(db.sales).insert(
    SalesCompanion.insert(
      id: id,
      userId: 'u1',
      deviceId: 'd1',
      totalMinor: 1000,
      status: Value(status),
      createdAtLocal: updatedAt ?? DateTime(2026, 9, 10, 10),
      updatedAtLocal: updatedAt ?? DateTime(2026, 9, 10, 12),
      clienteId: Value(clienteId),
    ),
  );

  Future<void> credito(String id, String saleId, String clienteId, int amount) =>
      db.into(db.creditSales).insert(
        CreditSalesCompanion.insert(
          id: id,
          saleId: saleId,
          clienteId: clienteId,
          amountMinor: amount,
          occurredAtMs: DateTime(2026, 9, 10, 12).toUtc().millisecondsSinceEpoch,
        ),
      );

  Future<void> abono(String id, String clienteId, int amount, DateTime when) =>
      db.into(db.customerPayments).insert(
        CustomerPaymentsCompanion.insert(
          id: id,
          clienteId: clienteId,
          amountMinor: amount,
          method: 'cash',
          occurredAtMs: when.toUtc().millisecondsSinceEpoch,
        ),
      );

  test('clientes sin movimientos tienen compras cero, sin adeudo y sin fecha', () async {
    await cliente('a', 'Ana');
    await cliente('b', 'Luis');
    final resumen = await repository.watchResumen().first;
    expect(resumen, hasLength(2));
    final ana = resumen.singleWhere((c) => c.id == 'a');
    expect(ana.compras, 0);
    expect(ana.ultimoMovimiento, isNull);
    expect(ana.saldoMinor, BigInt.zero);
  });

  test('compras cuentan ventas confirmadas de cualquier método', () async {
    await cliente('a', 'Ana');
    await venta('s1', 'a', updatedAt: DateTime(2026, 9, 10, 10));
    await venta('s2', 'a', updatedAt: DateTime(2026, 9, 11, 10));
    await venta('s3', 'a', updatedAt: DateTime(2026, 9, 12, 10));
    await credito('cr1', 's3', 'a', 5000);
    await venta(
      'borrador',
      'a',
      status: 'borrador',
      updatedAt: DateTime(2026, 9, 20, 10),
    );
    final resumen = await repository.watchResumen().first;
    final ana = resumen.singleWhere((c) => c.id == 'a');
    expect(ana.compras, 3);
  });

  test('saldo = abonos menos créditos; último movimiento es lo más reciente', () async {
    await cliente('a', 'Ana');
    final ventaTime = DateTime(2026, 9, 10, 12);
    final abonoTime = DateTime(2026, 9, 15, 9);
    await venta('s1', 'a', updatedAt: ventaTime);
    await credito('cr1', 's1', 'a', 5000);
    await abono('p1', 'a', 2000, abonoTime);
    final resumen = await repository.watchResumen().first;
    final ana = resumen.singleWhere((c) => c.id == 'a');
    expect(ana.compras, 1);
    expect(ana.saldoMinor, BigInt.from(-3000));
    expect(ana.ultimoMovimiento, abonoTime);
  });

  test('anticipo sin deuda genera saldo a favor y cuenta como movimiento', () async {
    await cliente('a', 'Ana');
    final when = DateTime(2026, 9, 20, 9);
    await abono('p1', 'a', 1500, when);
    final resumen = await repository.watchResumen().first;
    final ana = resumen.singleWhere((c) => c.id == 'a');
    expect(ana.saldoMinor, BigInt.from(1500));
    expect(ana.ultimoMovimiento, when);
    expect(ana.compras, 0);
  });

  test('un abono actualiza saldo en vivo y el saldo cero sale de la deuda', () async {
    await cliente('a', 'Ana');
    await venta('s1', 'a', updatedAt: DateTime(2026, 9, 10, 12));
    await credito('cr1', 's1', 'a', 5000);
    final stream = repository.watchResumen();
    final inicial = await stream.first;
    expect(inicial.singleWhere((c) => c.id == 'a').saldoMinor, BigInt.from(-5000));

    await abono('p1', 'a', 2000, DateTime(2026, 9, 15, 9));
    final conAbono = await stream.firstWhere(
      (list) =>
          list.singleWhere((c) => c.id == 'a').saldoMinor ==
          BigInt.from(-3000),
    );
    expect(conAbono.singleWhere((c) => c.id == 'a').saldoMinor, BigInt.from(-3000));

    await abono('p2', 'a', 3000, DateTime(2026, 9, 16, 9));
    final liquidado = await stream.firstWhere(
      (list) => list.singleWhere((c) => c.id == 'a').saldoMinor == BigInt.zero,
    );
    expect(liquidado.singleWhere((c) => c.id == 'a').saldoMinor, BigInt.zero);
  });
}