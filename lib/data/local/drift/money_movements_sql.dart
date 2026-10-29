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

  /// Salidas y correcciones de documentos conservados, por fecha de operación.
  /// El libro físico local conserva también incidencias. Una regularización
  /// aceptada no se suma otra vez si el efecto perdedor ya existe aquí.
  static const String appliedSaleAdjustments = r'''
    UNION ALL
    SELECT a.id,a.event_id,a.amount_minor,a.method,a.settlement_reference,
      a.occurred_at_ms,'sale_adjustment',a.sale_id,a.cliente_id,c.nombre,
      e.user_id,e.device_id,e.delivery_status,e.rejection_reason,'out'
    FROM sale_adjustments a JOIN events e ON e.event_id=a.event_id
    LEFT JOIN clientes c ON c.id=a.cliente_id
    WHERE e.application_status='applied' AND a.method IN ('cash','transfer') AND a.amount_minor>0
    UNION ALL
    SELECT r.effect_id,r.event_id,abs(r.delta),'transfer',NULL,
      CAST(json_extract(r.payload_json,'$.occurred_at_ms') AS INTEGER),'sale_reconciliation',
      e.aggregate_id,NULL,NULL,e.user_id,e.device_id,e.delivery_status,e.rejection_reason,
      CASE WHEN r.delta>0 THEN 'in' ELSE 'out' END
    FROM sale_reconciliation_effects r JOIN events e ON e.event_id=r.event_id
    WHERE r.ledger='transfer' AND r.applied_locally=1
      AND NOT EXISTS (SELECT 1 FROM sale_adjustments a WHERE a.id=r.target_id AND r.is_recovery=0)
  ''';
}
