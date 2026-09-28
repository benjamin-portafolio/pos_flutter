import '../models/sync_event.dart';
import '../payloads/saldo_cuenta_inicial_declarado_payload.dart';
import 'account_balance_baseline_projection.dart';

/// Puerta de la proyección local del saldo inicial declarado.
///
/// Provee además la transacción atómica, para que el command service haga
/// idempotencia y persistencia como una sola unidad de trabajo (mismo patrón
/// que `CashProjectionStore` en caja).
abstract interface class AccountBalanceBaselineProjectionStore {
  Future<T> atomic<T>(Future<T> Function() action);

  /// Baseline con esa identidad, exista o no.
  Future<AccountBalanceBaselineProjection?> find(String id);

  /// El único slot. Devuelve el baseline existente venga del terminal que
  /// venga, y `null` si todavía no se declaró ninguno. No es un `find` por
  /// identidad: es la comprobación de que el hecho se declara una sola vez.
  Future<AccountBalanceBaselineProjection?> only();

  /// Baseline que otro evento declaró, si existe. Es la vista que necesita la
  /// revalidación: con dos filas, `only()` no dice cuál es la ajena.
  Future<AccountBalanceBaselineProjection?> otherThan(String createdEventId);

  /// Inserta el hecho. No actualiza: si la identidad ya existe, falla el
  /// `primaryKey` y el handler decide antes.
  Future<void> insertBaseline(
    SyncEvent event,
    SaldoCuentaInicialDeclaradoPayload payload,
  );

  /// Avanza `last_server_sequence` al confirmar el servidor el evento. Nunca
  /// retrocede la secuencia.
  Future<void> acknowledge(String eventId, int sequence);
}
