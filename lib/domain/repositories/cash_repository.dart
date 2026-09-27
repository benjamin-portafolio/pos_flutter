import '../caja/cash_session.dart';

abstract interface class CashRepository {
  /// Incluye las cajas recibidas por sync para consulta, sin permisos de escritura.
  Stream<List<CashSession>> watchSessions();
}
