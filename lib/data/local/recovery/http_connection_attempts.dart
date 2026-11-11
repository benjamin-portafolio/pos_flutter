import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../application/config/app_config.dart';
import '../../../application/recovery/recovery_attempt_store.dart';
import '../../../application/recovery/recovery_destination_inspector.dart';
import 'http_recovery_destination_inspector.dart';

/// Keeps an attempt proof private and durable before making the first request.
class HttpConnectionAttempts {
  HttpConnectionAttempts(this.directory);
  final Directory directory;

  Future<Map<String, Object?>> health(Uri destination) =>
      _request(destination.resolve('/sync/health'));

  Future<Map<String, Object?>> bootstrap(
    Uri destination,
    String server,
    String generation,
  ) async {
    final uri = HttpRecoveryDestinationInspector.parseDestination(
      '$destination',
    );
    final attempt = await _attempt(['bootstrap', '$uri', server, generation]);
    return _request(
      uri.resolve('/sync/bootstrap/request'),
      headers: _headers(server, generation, attempt),
      body: const {},
    );
  }

  Future<Map<String, Object?>> recovery(
    Uri destination,
    String server,
    String generation,
    Map<String, Object?> package,
  ) async {
    final uri = HttpRecoveryDestinationInspector.parseDestination(
      '$destination',
    );
    final source = (package['cut'] as Map)['source'] as Map;
    final attempt = await _attempt([
      'recovery',
      '$uri',
      server,
      generation,
      package['package_id'],
      package['manifest_digest'],
      source['device_id'],
    ]);
    final id = attempt['request_id'];
    final result = await _request(
      uri.resolve('/recovery/connection-request'),
      headers: _headers(server, generation, attempt),
      body: {
        'request_id': id,
        'package_id': package['package_id'],
        'manifest_digest': package['manifest_digest'],
        'source_device_id': source['device_id'],
      },
    );
    return {...result, 'request_id': id};
  }

  Future<Map<String, Object?>> authorizeRecovery(
    Uri destination,
    Map<String, Object?> package, {
    required RecoveryDestinationInspector inspector,
    String? server,
    String? generation,
  }) async {
    final uri = HttpRecoveryDestinationInspector.parseDestination(
      '$destination',
    );
    final checkingEligibility = server == null;
    if (checkingEligibility) {
      final status = await health(uri);
      if (status['recovery_protocol'] != 1 ||
          status['sync_protocol'] != 2 ||
          status['commercial_recovery_complete'] != true) {
        throw const FormatException('Destino incompatible con recuperación.');
      }
      server = status['server_instance_id'] as String?;
      generation = status['generation_id'] as String?;
    }
    if (server == null || generation == null) {
      throw const FormatException('El destino no informó su identidad.');
    }
    final approval = await recovery(uri, server, generation, package);
    if (!checkingEligibility || approval['status'] != 'approved') {
      return {
        ...approval,
        'server_instance_id': server,
        'generation_id': generation,
      };
    }
    final report = await inspector.inspect(
      mode: AppMode.serverSync,
      destination: uri,
      token: approval['token'] as String,
    );
    if (report['server_instance_id'] != server ||
        report['generation_id'] != generation) {
      throw const FormatException('La identidad del destino cambió.');
    }
    return {...report, ...approval};
  }

  Future<Map<String, Object?>> _attempt(List<Object?> scope) async {
    final key = sha256.convert(utf8.encode(jsonEncode(scope)));
    final store = RecoveryAttemptStore(Directory('${directory.path}/$key'));
    return store.withFileLock(() async {
      final existing = await store.read();
      if (existing != null) return existing;
      final random = Random.secure();
      final proof = List.generate(
        32,
        (_) => random.nextInt(256),
      ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
      final attempt = <String, Object?>{
        'request_id': const Uuid().v4(),
        'proof': proof,
      };
      await store.write(attempt);
      return attempt;
    });
  }

  Map<String, String> _headers(
    String server,
    String generation,
    Map<String, Object?> attempt,
  ) => {
    'X-POS-Server': server,
    'X-POS-Generation': generation,
    'Authorization': 'Bearer ${attempt['proof']}',
  };

  Future<Map<String, Object?>> _request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    final client = http.Client();
    try {
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
      if (response.statusCode != 200) {
        final message = switch (response.statusCode) {
          401 || 403 => 'El servidor rechazó la autorización de este intento.',
          409 ||
          412 ||
          423 ||
          426 => 'Destino incompatible o reservado por otro intento.',
          404 => 'El servidor no admite el alta o la recuperación por URL.',
          _ =>
            'No se pudo comprobar el servidor (HTTP ${response.statusCode}).',
        };
        throw FormatException(message);
      }
      final bytes = <int>[];
      await for (final part in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        if (bytes.length + part.length > 1048576) {
          throw const FormatException(
            'Respuesta del servidor fuera de límite.',
          );
        }
        bytes.addAll(part);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Respuesta del servidor incompatible.');
      }
      return decoded;
    } finally {
      client.close();
    }
  }
}
