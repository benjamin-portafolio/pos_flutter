/// Persisted operational identity. It contains only enrollment-issued sync
/// credentials, never the authorization used to publish a recovery package.
class SyncInstallation {
  SyncInstallation(this.value, {required this.persist});
  Map<String, Object?>? value;
  final Future<void> Function(Map<String, Object?>) persist;
  bool get needsPull => value?['phase'] == 'needs_pull';
  Map<String, String> get headers {
    final binding = value?['binding'] as Map?;
    return binding == null
        ? const {}
        : {
            'X-POS-Protocol': '2',
            'X-POS-Server': binding['server_instance_id'] as String,
            'X-POS-Generation': binding['generation_id'] as String,
            'X-POS-Device': binding['device_id'] as String,
            'Authorization': 'Bearer ${binding['token']}',
          };
  }

  bool allows(Uri uri) {
    final current = value;
    if (current == null) return true;
    final endpoint = Uri.parse(current['endpoint'] as String);
    if (uri.scheme != endpoint.scheme ||
        uri.host != endpoint.host ||
        uri.port != endpoint.port) {
      return false;
    }
    return !needsPull || ['/sync/health', '/sync/pull'].contains(uri.path);
  }

  Future<void> _pending = Future.value();

  // Activation can finish after the last HTTP response has drained. Serialize
  // its persistence with relocation so it cannot restore the previous endpoint.
  Future<void> _update(
    Map<String, Object?> Function(Map<String, Object?>) change,
  ) {
    final operation = _pending.then((_) async {
      final current = value;
      if (current == null) throw StateError('No hay instalación vinculada.');
      final next = change(current);
      if (identical(next, current)) return;
      await persist(next);
      value = next;
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> relocate(String endpoint) =>
      _update((current) => {...current, 'endpoint': endpoint});

  Future<void> activate() async {
    if (value == null) return;
    await _update(
      (current) => current['phase'] == 'needs_pull'
          ? {...current, 'phase': 'active'}
          : current,
    );
  }
}
