import 'dart:convert';
import 'dart:io';
import '../../../application/recovery/baseline_bootstrap_transport.dart';

/// Canal dedicado de enrolamiento. Nunca escribe endpoint/configuración de sync.
class HttpBaselineBootstrapTransport implements BaselineBootstrapTransport {
  HttpBaselineBootstrapTransport({
    required this.baseUri,
    required this.serverInstanceId,
    required this.generationId,
    required String enrollmentToken,
  }) : _token = enrollmentToken {
    if (baseUri.scheme != 'https' &&
        !(baseUri.scheme == 'http' &&
            {'127.0.0.1', 'localhost', '::1'}.contains(baseUri.host))) {
      throw ArgumentError('Bootstrap requiere TLS fuera de loopback.');
    }
    if (baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw ArgumentError('Endpoint bootstrap inválido.');
    }
  }
  final Uri baseUri;
  final String serverInstanceId;
  final String generationId;
  final String _token;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  void close() => _client.close(force: true);
  Future<List<int>> _request(String path, int limit, [Object? body]) async {
    final request = await _client.openUrl(
      body == null ? 'GET' : 'POST',
      baseUri.resolve(path),
    );
    request.followRedirects = false;
    request.headers.set('X-POS-Protocol', '2');
    request.headers.set('X-POS-Server', serverInstanceId);
    request.headers.set('X-POS-Generation', generationId);
    request.headers.set('Authorization', 'Bearer $_token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('Bootstrap HTTP ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final part in response.timeout(const Duration(seconds: 30))) {
      if (bytes.length + part.length > limit) {
        throw const FormatException('Respuesta bootstrap demasiado grande.');
      }
      bytes.addAll(part);
    }
    return bytes;
  }

  @override
  Future<List<int>> descriptor() => _request('/sync/bootstrap', 16777216);
  @override
  Future<List<int>> chunk(int index) =>
      _request('/sync/bootstrap/chunks/$index', 4194304);
  @override
  Future<Map<String, Object?>> bind(String datasetId, String digest) async =>
      Map<String, Object?>.from(
        jsonDecode(
              utf8.decode(
                await _request('/sync/bindings', 100000, {
                  'protocol_version': 1,
                  'dataset_id': datasetId,
                  'bootstrap_digest': digest,
                }),
              ),
            )
            as Map,
      );
}
