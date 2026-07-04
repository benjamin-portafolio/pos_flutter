import 'dart:convert';

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

  static const supportedApiVersion = 1;

  final int statusCode;
  final String body;
  final String? status;
  final int? apiVersion;
  final int? latestServerSequence;
  final DateTime? serverTime;

  bool get isHttpSuccessful => statusCode >= 200 && statusCode < 300;

  bool get isCompatible => apiVersion == supportedApiVersion;

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
