import '../payloads/quotation_selection_snapshot.dart';
import 'sync_projection.dart';

class QuotationItemProjection extends SyncProjection {
  const QuotationItemProjection({
    required super.id,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
    required this.quotationId,
    required this.sortOrder,
    required this.selection,
  });
  final String quotationId;
  final int sortOrder;
  final QuotationSelectionSnapshot selection;
}
