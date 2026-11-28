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
import 'http_recovery_transport.dart';

/// Keeps an attempt proof private and durable before making the first request.
class HttpConnectionAttempts {
  HttpConnectionAttempts(
    this.directory, {
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final Directory directory;

  Future<Map<String, Object?>> health(Uri destination) =>
      _request(destination.resolve('/sync/health'));

  /// A bounded read validates the existing credential against the server's
  /// installed dataset. No cursor or event is applied to the local database.
  Future<void> verifyBinding(
    Uri destination,
    Map<String, Object?> installation,
    Map<String, Object?> health,
  ) async {
    final binding = installation['binding'] as Map;
    final cursor = '${health['baseline_high_watermark']}';
    if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(cursor)) {
      throw const FormatException('El servidor no informó un baseline válido.');
    }
    final result = await _request(
      destination
          .resolve('/sync/pull')
          .replace(
            queryParameters: {
              'since': cursor,
              'limit': '1',
              'device_id': binding['device_id'] as String,
            },
          ),
      headers: {
        'X-POS-Protocol': '2',
        'X-POS-Server': binding['server_instance_id'] as String,
        'X-POS-Generation': binding['generation_id'] as String,
        'X-POS-Device': binding['device_id'] as String,
        'Authorization': 'Bearer ${binding['token']}',
      },
    );
    if (result['events'] is! List ||
        result['next_cursor'] is! int ||
        result['has_more'] is! bool) {
      throw const FormatException('Respuesta de vinculación incompatible.');
    }
  }

  /// Reuse the original proof, never request approval as a new device/attempt.
  Future<Map<String, Object?>> verifyRecoveryRelocation(
    Map<String, Object?> journal,
    Uri destination,
  ) async {
    final uri = HttpRecoveryDestinationInspector.parseDestination(
      '$destination',
    );
    final status = await health(uri);
    final server = journal['server_instance_id'] as String;
    final generation = journal['generation_id'] as String;
    if (status['sync_protocol'] != 2 ||
        status['recovery_protocol'] != 1 ||
        status['server_instance_id'] != server ||
        status['generation_id'] != generation) {
      throw StateError(
        'La nueva dirección pertenece a otro servidor o generación. '
        'Se conserva el intento y su destino.',
      );
    }
    var token = journal['recovery_token'] as String;
    final package = journal['prepared_source'] as Map?;
    Map<String, Object?>? proof;
    RecoveryAttemptStore? newStore;
    if (journal['connection_request_id'] != null) {
      if (package == null) throw StateError('Falta el corte del intento.');
      final source = (package['cut'] as Map)['source'] as Map;
      List<Object?> scope(String endpoint) => [
        'recovery',
        endpoint,
        server,
        generation,
        package['package_id'],
        package['manifest_digest'],
        source['device_id'],
      ];
      final previous = HttpRecoveryDestinationInspector.parseDestination(
        journal['destination'] as String,
      );
      proof = await _scopeStore(scope('$previous')).read();
      if (proof == null ||
          proof['request_id'] != journal['connection_request_id']) {
        throw StateError(
          'No se encontró la autorización original del intento.',
        );
      }
      final approval = await _request(
        uri.resolve('/recovery/connection-request'),
        headers: _headers(server, generation, proof),
        body: {
          'request_id': proof['request_id'],
          'package_id': package['package_id'],
          'manifest_digest': package['manifest_digest'],
          'source_device_id': source['device_id'],
        },
      );
      if (approval['status'] != 'approved' || approval['token'] is! String) {
        throw StateError(
          'El destino no autorizó reanudar el intento original.',
        );
      }
      token = approval['token'] as String;
      newStore = _scopeStore(scope('$uri'));
    }
    final transport = HttpRecoveryTransport(
      mode: AppMode.serverSync,
      destination: uri,
      server: server,
      generation: generation,
      token: token,
      client: _clientFactory(),
    );
    try {
      final id =
          (journal['recovery_id'] ?? journal['connection_request_id'])
              as String?;
      Map<String, Object?> result;
      var foundSession = id != null;
      try {
        result = await transport.request(
          'GET',
          id == null ? '/recovery/eligibility' : '/recovery/sessions/$id',
        );
      } on RecoveryTransportFailure catch (error) {
        // A lost creation response may hide an already accepted session. Only
        // an explicit 404 permits falling back to eligibility before creation.
        if (id == null ||
            journal['recovery_id'] != null ||
            error.status != 404) {
          rethrow;
        }
        foundSession = false;
        result = await transport.request('GET', '/recovery/eligibility');
      }
      if (foundSession &&
          (result['recovery_id'] != id ||
              result['manifest_digest'] != journal['manifest_digest'])) {
        throw const FormatException(
          'La dirección no conserva la sesión y el paquete originales.',
        );
      }
      if (!foundSession && result['eligible'] != true) {
        throw StateError('El destino no admite continuar este intento.');
      }
    } finally {
      transport.close();
    }
    if (newStore != null && proof != null) {
      await newStore.withFileLock(() async {
        final existing = await newStore!.read();
        if (existing != null &&
            (existing['request_id'] != proof!['request_id'] ||
                existing['proof'] != proof['proof'])) {
          throw StateError(
            'La dirección ya tiene otra autorización conservada.',
          );
        }
        await newStore.write(proof!);
      });
    }
    return {'recovery_token': token};
  }

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
    final store = _scopeStore(scope);
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

  RecoveryAttemptStore _scopeStore(List<Object?> scope) {
    final key = sha256.convert(utf8.encode(jsonEncode(scope)));
    return RecoveryAttemptStore(Directory('${directory.path}/$key'));
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
    final client = _clientFactory();
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
