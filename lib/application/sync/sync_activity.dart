import 'package:flutter/foundation.dart';

/// Evidencia de los recorridos del orquestador; una conexión no la confirma.
class SyncActivity extends ChangeNotifier {
  int _running = 0;
  bool _failed = false;
  bool _verified = false;
  int _invalidation = 0;
  int _startedAtInvalidation = 0;
  DateTime? _verifiedAt;
  DateTime? get verifiedAt => _verifiedAt;
  bool _hasVerification = false;
  bool get hasVerification => _hasVerification;
  String? _error;
  String? get error => _error;

  bool get isRunning => _running > 0;

  void invalidate() {
    _invalidation++;
    _hasVerification = false;
    notifyListeners();
  }

  Future<T> run<T>(Future<T> Function() action, {bool verifies = false}) async {
    if (_running == 0) {
      _startedAtInvalidation = _invalidation;
      _failed = false;
      _verified = false;
      _error = null;
    }
    _running++;
    _hasVerification = false;
    notifyListeners();
    try {
      final result = await action();
      _verified |= verifies;
      return result;
    } catch (failure) {
      _failed = true;
      _error = failure.toString();
      rethrow;
    } finally {
      _running--;
      if (_running == 0 &&
          !_failed &&
          _verified &&
          _startedAtInvalidation == _invalidation) {
        _verifiedAt = DateTime.now();
        _hasVerification = true;
      }
      notifyListeners();
    }
  }
}
