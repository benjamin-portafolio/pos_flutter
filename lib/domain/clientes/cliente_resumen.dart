/// Resumen de un cliente para la pantalla de Gestión de clientes.
///
/// Se calcula con consultas locales agregadas (ventas confirmadas, abonos,
/// anticipos y créditos) y no representa un evento ni una tabla nueva.
class ClienteResumen {
  const ClienteResumen({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.active,
    required this.compras,
    required this.ultimoMovimiento,
    required this.saldoMinor,
  });

  final String id;
  final String nombre;
  final String? telefono;

  /// Falso cuando el cliente quedó inactivo por una incidencia.
  final bool active;

  /// Ventas confirmadas asociadas al cliente (efectivo, transferencia o
  /// crédito). Los abonos y anticipos no cuentan como compras.
  final int compras;

  /// Fecha local del último movimiento del cliente: venta confirmada, abono o
  /// anticipo. Nulo si el cliente no tiene movimientos.
  final DateTime? ultimoMovimiento;

  /// Saldo en centavos siguiendo la convención de la cuenta: negativo significa
  /// adeudo, cero significa sin adeudo y positivo significa saldo a favor.
  final BigInt saldoMinor;
}