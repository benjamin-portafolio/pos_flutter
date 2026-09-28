import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/transfer_summary.dart';
import 'package:pos_flutter/domain/repositories/transfer_summary_repository.dart';

/// Doble de `TransferSummaryRepository` para pruebas de pantalla.
///
/// Registra cada ventana pedida en [windows] para poder afirmar sobre el
/// periodo consultado, y responde con el agregado que [_build] devuelve para
/// esa ventana.
class FakeTransferSummaryRepository implements TransferSummaryRepository {
  FakeTransferSummaryRepository(this._build, {this.falla = false});

  /// Agregado por ventana `[fromMs, toMs)`.
  final TransferSummary Function(int fromMs, int toMs) _build;

  /// Si es `true`, el stream emite un error en vez del agregado.
  final bool falla;

  /// Ventanas consultadas, en orden.
  final List<({int fromMs, int toMs})> windows = [];

  @override
  Stream<TransferSummary> watchTransferSummary({
    required int fromMs,
    required int toMs,
  }) {
    windows.add((fromMs: fromMs, toMs: toMs));
    if (falla) return Stream.error(StateError('sin base local'));
    return Stream.value(_build(fromMs, toMs));
  }
}

/// Resumen vacio para `[fromMs, toMs)`: periodo sin una sola transferencia.
TransferSummary emptyTransferSummary(int fromMs, int toMs) =>
    TransferSummary.fromMovements(
      fromMs: fromMs,
      toMs: toMs,
      movements: const [],
    );

/// Movimientos de prueba: [entradas] de 10.00 y [salidas] de 5.00, todas por
/// transferencia y con el signo ya resuelto.
List<TransferMovement> transferMovements({
  int entradas = 0,
  int salidas = 0,
  int occurredAtMs = 0,
}) => [
  for (var i = 0; i < entradas; i++)
    TransferMovement(
      id: 'in-$i',
      eventId: 'event-in-$i',
      origin: TransferOrigin.financialEntry,
      method: 'transfer',
      amountMinor: 1000,
      occurredAtMs: occurredAtMs,
      direction: FinancialDirection.income,
    ),
  for (var i = 0; i < salidas; i++)
    TransferMovement(
      id: 'out-$i',
      eventId: 'event-out-$i',
      origin: TransferOrigin.financialEntry,
      method: 'transfer',
      amountMinor: 500,
      occurredAtMs: occurredAtMs,
      direction: FinancialDirection.expense,
    ),
];
