import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../application/config/app_config.dart';
import '../../../application/recovery/recovery_transport.dart';
import 'http_recovery_destination_inspector.dart';

/// Recovery credentials never enter the operational sync client or endpoint.
class HttpRecoveryTransport implements RecoveryTransport {
  HttpRecoveryTransport({
    required AppMode mode,
    required Uri destination,
    required this.server,
    required this.generation,
    required this.token,
    http.Client? client,
  }) : destination = HttpRecoveryDestinationInspector.parseDestination(
         destination.toString(),
       ),
       _client = client ?? http.Client() {
    if (mode != AppMode.serverSync) {
      throw StateError('Standalone no admite red.');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const FormatException('Credencial de recuperación inválida.');
    }
  }
  final Uri destination;
  final String server, generation, token;
  final http.Client _client;
  @override
  Future<Map<String, Object?>> request(
    String method,
    String path, {
    List<int>? bytes,
    Map<String, String> headers = const {},
  }) async {
    if (!RegExp(
      r'^/recovery/(sessions(?:/[0-9a-f-]{36}(?:/(?:chunks/[0-9]+|validate|finalize|abort))?)?(?:\?offset=[0-9]+)?|eligibility)$',
    ).hasMatch(path)) {
      throw ArgumentError('Ruta de recuperación inválida.');
    }
    final request = http.Request(method, destination.resolve(path))
      ..followRedirects = false;
    request.headers.addAll({
      'X-POS-Protocol': '1',
      'X-POS-Server': server,
      'X-POS-Generation': generation,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      ...headers,
    });
    if (bytes != null) request.bodyBytes = bytes;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final result = <int>[];
    await for (final part in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      if (result.length + part.length > 16777216) {
        throw const FormatException(
          'Respuesta de recuperación demasiado grande.',
        );
      }
      result.addAll(part);
    }
    final decoded = jsonDecode(utf8.decode(result));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Respuesta de recuperación incompatible.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RecoveryTransportFailure(
        response.statusCode,
        decoded['code']?.toString() ?? 'destination_rejected',
      );
    }
    if (decoded['protocol_version'] != 1 ||
        decoded['server_instance_id'] != server ||
        decoded['generation_id'] != generation) {
      throw const FormatException('Respuesta de otra identidad o generación.');
    }
    return decoded;
  }

  @override
  void close() => _client.close();
}

class RecoveryTransportFailure extends FormatException {
  RecoveryTransportFailure(this.status, this.code)
    : super('Recuperación rechazada (HTTP $status, $code).');
  final int status;
  final String code;
  @override
  String toString() => 'Recuperación rechazada (HTTP $status, $code).';
}
