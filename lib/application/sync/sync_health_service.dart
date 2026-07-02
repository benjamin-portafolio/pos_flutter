import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_endpoint_config.dart';

class SyncHealthService {
  SyncHealthService({
    required SyncEndpointConfig endpointConfig,
    http.Client? client,
    Duration timeout = const Duration(seconds: 2),
  }) : _endpointConfig = endpointConfig,
       _client = client ?? http.Client(),
       _timeout = timeout;

  static const supportedApiVersion = 1;

  final SyncEndpointConfig _endpointConfig;
  final http.Client _client;
  final Duration _timeout;

  Future<SyncHealthCheck> check() async {
    final uri = Uri.parse('${_endpointConfig.baseUrl}/sync/health');

    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);

      return SyncHealthCheck.fromResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } on TimeoutException {
      throw const SyncHealthException(
        'Tiempo de espera agotado comprobando el servidor.',
      );
    } on SyncHealthException {
      rethrow;
    } catch (error) {
      throw SyncHealthException('Error comprobando el servidor: $error');
    }
  }
}

class SyncHealthCheck {
  const SyncHealthCheck({
    required this.statusCode,
    required this.body,
    required this.status,
    required this.apiVersion,
    required this.latestServerSequence,
    required this.serverTime,
  });

  factory SyncHealthCheck.fromResponse({
    required int statusCode,
    required String body,
  }) {
    final data = _decodeBody(body);

    return SyncHealthCheck(
      statusCode: statusCode,
      body: body,
      status: data['status'] as String?,
      apiVersion: _readInt(data['api_version']),
      latestServerSequence: _readInt(data['latest_server_sequence']),
      serverTime: _readDateTime(data['server_time']),
    );
  }

  final int statusCode;
  final String body;
  final String? status;
  final int? apiVersion;
  final int? latestServerSequence;
  final DateTime? serverTime;

  bool get isHttpSuccessful => statusCode >= 200 && statusCode < 300;

  bool get isCompatible => apiVersion == SyncHealthService.supportedApiVersion;

  bool get isAvailable => isHttpSuccessful && status == 'ok' && isCompatible;

  bool get isMisconfigured {
    if (statusCode >= 400 && statusCode < 500) return true;
    return isHttpSuccessful && !isAvailable;
  }

  String get failureMessage {
    if (!isHttpSuccessful) return 'HTTP $statusCode';
    if (status != 'ok') return 'Respuesta health invalida.';
    if (!isCompatible) return 'Version de sync no compatible.';
    return 'Servidor no disponible.';
  }

  static Map<String, Object?> _decodeBody(String body) {
    if (body.trim().isEmpty) return const <String, Object?>{};

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return const <String, Object?>{};
    }

    return const <String, Object?>{};
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}

class SyncHealthException implements Exception {
  const SyncHealthException(this.message);

  final String message;

  @override
  String toString() => message;
}
