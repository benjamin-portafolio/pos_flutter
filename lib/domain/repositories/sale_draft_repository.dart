import '../ventas/sale_draft.dart';

abstract interface class SaleDraftRepository {
  Stream<SaleDraft?> watchCurrentDraft();
}
