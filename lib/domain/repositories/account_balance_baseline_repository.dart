import '../cuenta/account_balance_baseline.dart';

/// Lectura del hecho «saldo inicial declarado». No crea sesión ni emite eventos:
/// el único hecho posible, se consulta o no existe.
abstract interface class AccountBalanceBaselineRepository {
  /// El baseline declarado, elija terminal. `null` mientras no se declare.
  /// Cambia cuando se declara, cuando llega por sync o cuando el servidor
  /// confirma la entrega.
  Stream<AccountBalanceBaseline?> watchBaseline();
}
