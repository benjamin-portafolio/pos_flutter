import 'package:pos_flutter/domain/repositories/sale_draft_repository.dart';
import 'package:pos_flutter/domain/ventas/sale_draft.dart';

class FakeSaleDraftRepository implements SaleDraftRepository {
  FakeSaleDraftRepository([this.source]);
  final Stream<SaleDraft?> Function()? source;

  @override
  String? selectedDraftId;

  @override
  void selectDraft(String saleId) => selectedDraftId = saleId;

  @override
  Stream<List<SaleDraft>> watchDrafts() =>
      watchCurrentDraft().map((sale) => [?sale]);

  @override
  Stream<SaleDraft?> watchCurrentDraft() =>
      source?.call() ?? Stream.value(null);
}
