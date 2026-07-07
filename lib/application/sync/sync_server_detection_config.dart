import 'dart:async';

class SyncServerDetectionConfig {
  SyncServerDetectionConfig({bool requireWifiForServerDetection = false})
    : _requireWifiForServerDetection = requireWifiForServerDetection;

  final _changes = StreamController<bool>.broadcast();

  bool _requireWifiForServerDetection;

  bool get requireWifiForServerDetection => _requireWifiForServerDetection;

  Stream<bool> get requireWifiForServerDetectionChanges => _changes.stream;

  void updateRequireWifiForServerDetection(bool value) {
    if (_requireWifiForServerDetection == value) return;

    _requireWifiForServerDetection = value;
    if (!_changes.isClosed) {
      _changes.add(value);
    }
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}
