/// Política compartida por comprobación, transferencia y vinculación.
class RecoveryDestinationPolicy {
  static const allowLocalHttp = bool.fromEnvironment('POS_ALLOW_LOCAL_HTTP');

  static Uri parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !_allowsTransport(uri)) {
      throw const FormatException(
        allowLocalHttp
            ? 'Usa una URL HTTPS o HTTP con IP privada local, sin credenciales ni ruta.'
            : 'Usa una URL HTTPS completa, sin credenciales ni ruta.',
      );
    }
    return uri.replace(path: '');
  }

  static bool _allowsTransport(Uri uri) {
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    if ({'localhost', '127.0.0.1', '::1'}.contains(uri.host)) return true;
    if (!allowLocalHttp) return false;
    // Solo IPv4 privada literal: no aceptar dominios que puedan resolver fuera
    // de la LAN ni relajar la política para servidores públicos.
    final parts = uri.host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((n) => n == null || n < 0 || n > 255)) return false;
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }
}
