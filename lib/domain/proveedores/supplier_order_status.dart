/// Estados del documento; confirmación y cancelación nunca son movimientos.
enum SupplierOrderStatus {
  draft,
  confirmed,
  partial,
  received,
  closed,
  cancelled;

  bool canTransitionTo(SupplierOrderStatus next) => switch (this) {
    draft => {draft, confirmed, cancelled}.contains(next),
    confirmed => {partial, received, closed, cancelled}.contains(next),
    partial => {partial, received, closed}.contains(next),
    received || closed || cancelled => false,
  };
}
