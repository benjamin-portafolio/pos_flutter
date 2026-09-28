/// Forma normalizada del dinero ya aplicado (H1), compartida para que el
/// agregado de cobros y el de transferencias no se dupliquen (R5).
///
/// El shape vive aquí y no dentro de un repositorio: cada consulta lo extiende
/// con sus ramas y sus filtros. Cambiar `method`, `occurred_at_ms` o el estado
/// de aplicación se hace en un solo lugar.
///
/// No se une `credit_allocations`: repartir o aplicar un anticipo no recibe
/// dinero, es proyección FIFO reconstruible.
abstract final class MoneyMovementsSql {
  /// Columnas del shape, en el orden que fija la primera rama del UNION.
  /// `direction` es la fuente del signo (H4) y se materializa en las tres
  /// ramas: `sale_payments` y `customer_payments` solo reciben, así que emiten
  /// el literal `in`.
  static const String columns = '''
    id, event_id, amount_minor, method, reference, occurred_at_ms, origin,
    sale_id, cliente_id, cliente_nombre, user_id, device_id, delivery_status,
    rejection_reason, direction''';

  /// `sale_payments` y `customer_payments` aplicadas, verbatim del SELECT de
  /// collections. `sale_payments` no tiene timestamp propio (H1b), así que su
  /// fecha se deriva de `events.created_at_local` por join; no cambiar esa
  /// derivación aquí.
  static const String appliedSalesAndCustomerPayments = '''
    SELECT p.id AS id, p.created_event_id AS event_id, p.amount_minor, p.method, p.reference,
      e.created_at_local * 1000 AS occurred_at_ms, 'sale' AS origin,
      p.sale_id, s.cliente_id, c.nombre AS cliente_nombre,
      e.user_id, e.device_id, e.delivery_status, e.rejection_reason,
      'in' AS direction
    FROM sale_payments p JOIN sales s ON s.id = p.sale_id
    JOIN events e ON e.event_id = p.created_event_id
    LEFT JOIN clientes c ON c.id = s.cliente_id
    WHERE e.application_status = 'applied'
    UNION ALL
    SELECT p.id, p.created_event_id, p.amount_minor, p.method, p.reference,
      p.occurred_at_ms, 'customer_payment', NULL, p.cliente_id, c.nombre,
      e.user_id, e.device_id, e.delivery_status, e.rejection_reason,
      'in'
    FROM customer_payments p JOIN events e ON e.event_id = p.created_event_id
    JOIN clientes c ON c.id = p.cliente_id
    WHERE e.application_status = 'applied'
  ''';
}
