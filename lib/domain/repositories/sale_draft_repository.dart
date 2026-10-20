import '../ventas/sale_draft.dart';

abstract interface class SaleDraftRepository {
  /// Borradores abiertos del usuario y dispositivo, en orden de creación.
  Stream<List<SaleDraft>> watchDrafts();

  /// Selección local de Caja; puede identificar una pestaña aún vacía.
  String? get selectedDraftId;
  void selectDraft(String saleId);

  Stream<SaleDraft?> watchCurrentDraft();
}
