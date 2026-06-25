class SyncEndpointConfig {
  SyncEndpointConfig({String initialBaseUrl = defaultBaseUrl})
    : _baseUrl = normalizeBaseUrl(initialBaseUrl);

  static const String defaultBaseUrl = 'http://10.0.2.2:3000';

  String _baseUrl;

  String get baseUrl => _baseUrl;

  void updateFromInput(String input) {
    _baseUrl = normalizeBaseUrl(input);
  }

  static String normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Ingresa la IP o URL del servidor.');
    }

    final hasScheme = trimmed.contains('://');
    final value = hasScheme ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Servidor invalido.');
    }

    final normalized = !hasScheme && !uri.hasPort
        ? uri.replace(port: 3000, path: '', query: null, fragment: null)
        : uri.replace(path: '', query: null, fragment: null);

    return normalized.toString();
  }
}
