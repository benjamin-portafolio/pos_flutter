import '../finanzas/transfer_summary.dart';

/// Agregación local de transferencias para el saldo estimado de la cuenta
/// bancaria. Consulta pura: no crea sesión, no emite eventos y no toca caja.
abstract interface class TransferSummaryRepository {
  /// Agregado de las transferencias con `method = 'transfer'` ocurridas en
  /// `[fromMs, toMs)`, sobre los tres origenes de dinero: ventas, abonos de
  /// cliente y movimientos financieros, con signo resuelto y totales `BigInt`.
  ///
  /// Incluye lo aplicado localmente con cualquier estado de entrega, igual que
  /// el informe de cobros: lo pendiente de sync es dinero que ya se movió.
  Stream<TransferSummary> watchTransferSummary({
    required int fromMs,
    required int toMs,
  });
}
