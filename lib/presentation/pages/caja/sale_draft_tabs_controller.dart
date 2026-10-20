import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/repositories/sale_draft_repository.dart';
import '../../../domain/ventas/sale_draft.dart';

typedef SaleDraftTabsSnapshot = ({List<String> ids, Set<String> persistedIds});

/// Las pestañas vacías son locales a la sesión; las compras se guardan por eventos.
class SaleDraftTabsController extends ChangeNotifier {
  SaleDraftTabsController(this.repository, {SaleDraftTabsSnapshot? snapshot}) {
    if (snapshot != null) {
      _ids.addAll(snapshot.ids);
      _persistedIds = snapshot.persistedIds.toSet();
    }
    _drafts = repository.watchDrafts().listen(_update, onError: _ignoreError);
    _selection = repository.watchCurrentDraft().listen(
      (_) => notifyListeners(),
      onError: _ignoreError,
    );
  }

  final SaleDraftRepository repository;
  final _ids = <String>[];
  Set<String> _persistedIds = {};
  late final StreamSubscription<List<SaleDraft>> _drafts;
  late final StreamSubscription<SaleDraft?> _selection;
  static const _uuid = Uuid();

  SaleDraftTabsSnapshot get snapshot =>
      (ids: List.of(_ids), persistedIds: Set.of(_persistedIds));

  int get length => _ids.length;
  bool get ready => _ids.isNotEmpty;
  int get selectedIndex {
    final selected = repository.selectedDraftId;
    return selected == null ? -1 : _ids.indexOf(selected);
  }

  void select(int index) {
    repository.selectDraft(_ids[index]);
    notifyListeners();
  }

  void add() {
    _ids.add(_uuid.v4());
    select(_ids.length - 1);
  }

  void _update(List<SaleDraft> drafts) {
    final currentIds = drafts.map((draft) => draft.id).toSet();
    final selected = repository.selectedDraftId;
    if (_ids.isEmpty) {
      _ids.addAll(currentIds);
      if (selected != null && !_ids.contains(selected)) {
        _ids.insert(0, selected);
      }
    } else {
      // Un ID cobrado o limpiado nunca vuelve a usarse para una captura nueva.
      for (var i = 0; i < _ids.length; i++) {
        if (_persistedIds.contains(_ids[i]) && !currentIds.contains(_ids[i])) {
          final removed = _ids[i];
          _ids[i] = _uuid.v4();
          if (selected == removed) repository.selectDraft(_ids[i]);
        }
      }
      for (final id in currentIds) {
        if (_ids.contains(id)) continue;
        final empty = _ids.indexWhere((slot) => !currentIds.contains(slot));
        if (empty < 0) {
          _ids.add(id);
        } else {
          final previous = _ids[empty];
          _ids[empty] = id;
          if (repository.selectedDraftId == previous) {
            repository.selectDraft(id);
          }
        }
      }
    }
    while (_ids.length < 2) {
      _ids.add(_uuid.v4());
    }
    _persistedIds = currentIds;
    if (repository.selectedDraftId == null) repository.selectDraft(_ids.first);
    notifyListeners();
  }

  // Caja presenta los errores del mismo repositorio en su vista de venta.
  void _ignoreError(Object error, StackTrace stack) {}

  @override
  void dispose() {
    unawaited(_drafts.cancel());
    unawaited(_selection.cancel());
    super.dispose();
  }
}
