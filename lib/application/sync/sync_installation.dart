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

  Future<void> activate() async {
    final current = value;
    if (current == null || !needsPull) return;
    final active = <String, Object?>{...current, 'phase': 'active'};
    await persist(active);
    value = active;
  }
}
