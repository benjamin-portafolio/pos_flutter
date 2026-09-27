import '../clientes/cliente_resumen.dart';

/// Proporciona los resúmenes de clientes para el listado de Gestión de clientes.
abstract interface class ClienteResumenRepository {
  /// Emite los resúmenes cada vez que cambian los clientes, ventas confirmadas,
  /// abonos, anticipos o créditos locales.
  Stream<List<ClienteResumen>> watchResumen();
}