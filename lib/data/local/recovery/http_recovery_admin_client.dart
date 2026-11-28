import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../application/config/app_config.dart';
import '../../../application/recovery/recovery_admin_client.dart';
import '../../../application/recovery/recovery_destination_policy.dart';

class HttpRecoveryAdminClient implements RecoveryAdminClient {
  HttpRecoveryAdminClient({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  http.Client? _active;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  @override
  void cancel() {
    _active?.close();
    _active = null;
  }

  Future<T> _using<T>(
    AppMode mode,
    String destination,
    String credential,
    Future<T> Function(http.Client, Uri) fn,
  ) async {
    if (mode != AppMode.serverSync) {
      throw StateError('Administración disponible solo en modo servidor.');
    }
    final uri = RecoveryDestinationPolicy.parse(destination);
    if (credential.isEmpty ||
        credential.runes.length > 128 ||
        utf8.encode(credential).length > 512 ||
        RegExp(r'[\p{Cc}\p{Cs}]', unicode: true).hasMatch(credential)) {
      throw const FormatException(
        'Ingresa tu contraseña administrativa (hasta 128 caracteres, sin saltos de línea).',
      );
    }
    if (_active != null) {
      throw StateError('Ya hay una operación administrativa en curso.');
    }
    final client = _clientFactory();
    _active = client;
    try {
      return await fn(client, uri);
    } on TimeoutException {
      throw const FormatException(
        'El servidor no respondió a tiempo. Consulta el estado antes de repetir una acción.',
      );
    } on http.ClientException {
      throw const FormatException(
        'No se pudo conectar. Consulta el estado antes de repetir una acción.',
      );
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  Map<String, String> _headers(String credential, Map<String, Object?> s) => {
    'Authorization': RegExp(r'^[0-9a-f]{64}$').hasMatch(credential)
        ? 'Bearer $credential'
        : 'Basic ${base64Encode(utf8.encode('admin:$credential'))}',
    'X-POS-Protocol': '1',
    'X-POS-Server': s['server_instance_id'] as String,
    'X-POS-Generation': s['generation_id'] as String,
  };

  void _identity(Map<String, Object?> s) {
    if (s['server_instance_id'] is! String ||
        !_uuid.hasMatch(s['server_instance_id'] as String) ||
        s['generation_id'] is! String ||
        !_uuid.hasMatch(s['generation_id'] as String)) {
      throw const FormatException(
        'El servidor no entregó una identidad compatible.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> inspect({
    required AppMode mode,
    required String destination,
    required String credential,
  }) => _using(mode, destination, credential, (client, uri) async {
    final health = await _request(client, uri.resolve('/sync/health'));
    _identity(health);
    if (health['recovery_protocol'] != 1 || health['sync_protocol'] != 2) {
      throw const FormatException(
        'El servidor no es compatible con esta administración.',
      );
    }
    final result = await _request(
      client,
      uri.resolve('/recovery-admin/status'),
      headers: _headers(credential, health),
    );
    _identity(result);
    final eligibility = result['eligibility'];
    if (result['protocol_version'] != 1 ||
        result['server_instance_id'] != health['server_instance_id'] ||
        result['generation_id'] != health['generation_id'] ||
        result['revision'] is! int ||
        result['recovery_enabled'] is! bool ||
        result['requests'] is! List ||
        eligibility is! Map ||
        eligibility['eligible'] is! bool ||
        eligibility['reasons'] is! List) {
      throw const FormatException(
        'El estado administrativo recibido es incompatible.',
      );
    }
    return result;
  });

  @override
  Future<void> execute({
    required AppMode mode,
    required String destination,
    required String credential,
    required Map<String, Object?> snapshot,
    required String action,
    String? requestId,
  }) => _using(mode, destination, credential, (client, uri) async {
    _identity(snapshot);
    if (!{
          'enable',
          'disable',
          'approve',
          'reject',
          'enrollment-enable',
          'enrollment-disable',
        }.contains(action) ||
        snapshot['revision'] is! int ||
        ({'approve', 'reject'}.contains(action) &&
            (requestId == null || !_uuid.hasMatch(requestId)))) {
      throw const FormatException('Acción administrativa inválida.');
    }
    final result = await _request(
      client,
      uri.resolve('/recovery-admin/actions'),
      headers: _headers(credential, snapshot),
      body: {
        'action': action,
        'expected_revision': snapshot['revision'],
        'request_id': ?requestId,
      },
    );
    if (result['protocol_version'] != 1 ||
        result['server_instance_id'] != snapshot['server_instance_id'] ||
        result['generation_id'] != snapshot['generation_id'] ||
        result['action'] != action ||
        result['revision'] != (snapshot['revision'] as int) + 1) {
      throw const FormatException(
        'Respuesta inesperada. Consulta el estado antes de repetir la acción.',
      );
    }
  });

  Future<Map<String, Object?>> _request(
    http.Client client,
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(body == null ? 'GET' : 'POST', uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 15));
    final bytes = <int>[];
    await for (final part in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (bytes.length + part.length > 2097152) {
        throw const FormatException(
          'Respuesta administrativa fuera de límite.',
        );
      }
      bytes.addAll(part);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FormatException(
        'Credencial administrativa inválida o acceso no autorizado.',
      );
    }
    if (response.statusCode == 503) {
      throw const FormatException(
        'La administración de recuperación no está configurada en el servidor.',
      );
    }
    if (response.statusCode == 409) {
      throw const FormatException(
        'El estado cambió o la acción no está permitida. Actualiza el estado del servidor.',
      );
    }
    if (response.statusCode != 200) {
      throw FormatException(
        'El servidor rechazó la operación (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Respuesta administrativa incompatible.');
    }
    return decoded;
  }
}
