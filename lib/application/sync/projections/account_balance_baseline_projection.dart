/// Proyección local del saldo inicial declarado.
///
/// No tiene estado operativo ni ciclo de vida: no hay `status`, no hay cierre y
/// no hay versión que avanzar. Los campos de `CommonFields` están para poder
/// hacer el join a `events` por `last_event_id` y obtener `delivery_status` y
/// `rejection_reason`, que es como `CashRepositoryImpl` lo resuelve para caja.
class AccountBalanceBaselineProjection {
  const AccountBalanceBaselineProjection({
    required this.id,
    required this.active,
    required this.version,
    required this.createdEventId,
    required this.lastEventId,
    required this.lastServerSequence,
    required this.deviceId,
    required this.declaredByUserId,
    required this.amountMinor,
    required this.asOfMs,
  });

  final String id;
  final bool active;
  final int version;
  final String? createdEventId;
  final String? lastEventId;
  final int? lastServerSequence;
  final String deviceId;
  final String declaredByUserId;
  final int amountMinor;
  final int asOfMs;
}
