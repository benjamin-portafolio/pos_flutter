import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../application/config/app_config.dart';
import '../../../application/recovery/recovery_destination_inspector.dart';

/// Canal independiente, TLS salvo loopback; no sigue redirecciones ni hace push.
class HttpRecoveryDestinationInspector implements RecoveryDestinationInspector {
  HttpRecoveryDestinationInspector({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;

  http.Client? _activeClient;

  @override
  void cancel() {
    _activeClient?.close();
    _activeClient = null;
  }

  static Uri parseDestination(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                {'localhost', '127.0.0.1', '::1'}.contains(uri.host)))) {
      throw const FormatException(
        'Usa una URL HTTPS completa, sin credenciales ni ruta.',
      );
    }
    return uri.replace(path: '');
  }

  @override
  Future<Map<String, Object?>> inspect({
    required AppMode mode,
    required Uri destination,
    required String token,
  }) async {
    if (mode != AppMode.serverSync) {
      throw StateError('Standalone solo permite diagnóstico local.');
    }
    final uri = parseDestination(destination.toString());
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const FormatException(
        'Ingresa la credencial de recuperación emitida por el operador.',
      );
    }
    if (_activeClient != null) {
      throw StateError('Ya hay una comprobación en curso.');
    }
    final client = _clientFactory();
    _activeClient = client;
    try {
      final health = await _get(client, uri.resolve('/sync/health'), {});
      final server = health['server_instance_id'];
      final generation = health['generation_id'];
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      );
      if (health['recovery_protocol'] != 1 ||
          health['sync_protocol'] != 2 ||
          server is! String ||
          !uuid.hasMatch(server) ||
          generation is! String ||
          !uuid.hasMatch(generation)) {
        throw const FormatException(
          'Servidor incompatible con recuperación segura.',
        );
      }
      final result = await _get(client, uri.resolve('/recovery/eligibility'), {
        'Authorization': 'Bearer $token',
        'X-POS-Protocol': '1',
        'X-POS-Server': server,
        'X-POS-Generation': generation,
      });
      if (result['protocol_version'] != 1 ||
          result['server_instance_id'] != server ||
          result['generation_id'] != generation ||
          result['eligible'] is! bool ||
          result['reasons'] is! List ||
          result['counts'] is! Map ||
          result['schema_fingerprint'] is! String) {
        throw const FormatException(
          'Identidad o respuesta de elegibilidad incompatible.',
        );
      }
      // El contador health no decide vacío. Se conserva el informe vinculable
      // a esta identidad, pero esta consulta no constituye una reserva.
      return result;
    } on TimeoutException {
      throw const FormatException(
        'El destino no respondió a tiempo. Puedes volver a comprobar.',
      );
    } on http.ClientException {
      throw const FormatException('No se pudo conectar con el destino.');
    } finally {
      client.close();
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  Future<Map<String, Object?>> _get(
    http.Client client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 15));
    final bytes = <int>[];
    await for (final part in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (bytes.length + part.length > 1048576) {
        throw const FormatException('Respuesta del destino fuera de límite.');
      }
      bytes.addAll(part);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FormatException(
        'Recuperación no autorizada o credencial vencida.',
      );
    }
    if (response.statusCode != 200) {
      throw FormatException(
        'El destino rechazó la comprobación (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Respuesta del destino incompatible.');
    }
    return decoded;
  }
}
