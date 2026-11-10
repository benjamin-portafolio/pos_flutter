import 'package:http/http.dart' as http;
import '../../../application/sync/sync_installation.dart';
import '../../../application/sync/sync_network_gate.dart';

/// Todos los transportes HTTP operativos registrados comparten la compuerta.
class GuardedSyncClient extends http.BaseClient {
  GuardedSyncClient(this.gate, this.inner, {this.installation});
  final SyncInstallation? installation;
  final SyncNetworkGate gate;
  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (installation?.allows(request.url) == false) {
      throw StateError(
        'El endpoint o la activación de esta generación no admite esta operación.',
      );
    }
    request.headers.addAll(installation?.headers ?? const {});
    if (installation?.value != null) request.followRedirects = false;
    gate.beginRequest();
    try {
      final response = await inner.send(request);
      return http.StreamedResponse(
        _consume(response.stream),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      gate.endRequest();
      rethrow;
    }
  }

  Stream<List<int>> _consume(Stream<List<int>> stream) async* {
    try {
      yield* stream;
    } finally {
      gate.endRequest();
    }
  }

  @override
  void close() => inner.close();
}
