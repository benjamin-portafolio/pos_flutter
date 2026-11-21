import '../proveedores/replenishment_candidate.dart';
import '../proveedores/supplier_order_failed_attempt.dart';
import '../proveedores/replenishment_issue.dart';
import '../proveedores/supplier_order_summary.dart';

abstract interface class SupplierOrderRepository {
  Stream<List<ReplenishmentCandidate>> watchCandidates();
  Stream<List<ReplenishmentIssue>> watchIssues();
  Stream<List<SupplierOrderSummary>> watchOrders();
  Stream<List<SupplierOrderFailedAttempt>> watchFailedAttempts();
}
