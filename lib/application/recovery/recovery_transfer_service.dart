import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';
import 'recovery_attempt_store.dart';
import 'recovery_cancellation.dart';
import 'recovery_json.dart';
import 'recovery_package_reader.dart';
import 'recovery_transport.dart';

/// Durable S2/S4 orchestration. Resumes by asking the server, never by guessing
/// whether a request that lost its response committed.
class RecoveryTransferService {
  RecoveryTransferService(this.store);
  final RecoveryAttemptStore store;
  bool _busy = false;
  Future<void> archive(Directory history) async {
    if (_busy) throw StateError('Ya existe una operación en curso.');
    _busy = true;
    try {
      final current = await store.read();
      if (current == null ||
          !['completed', 'aborted'].contains(current['state'])) {
        throw StateError('Solo se archivan intentos terminados.');
      }
      await history.create(recursive: true);
      await store.directory.rename(
        '${history.path}/${current['package_id']}-${DateTime.now().millisecondsSinceEpoch}',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> reopen(Directory history, String key) async {
    if (_busy) throw StateError('Ya existe una operación en curso.');
    _busy = true;
    try {
      if (!RegExp(r'^[0-9a-f-]{36}-[0-9]{13,}$').hasMatch(key)) {
        throw const FormatException('Historial incompatible.');
      }
      final archived = RecoveryAttemptStore(Directory('${history.path}/$key'));
      final record = await archived.read();
      if (record == null ||
          !['completed', 'aborted'].contains(record['state'])) {
        throw const FormatException('Historial no terminado o incompatible.');
      }
      if (await store.read() != null) {
        throw StateError(
          'Conserva o termina el intento actual antes de abrir otro.',
        );
      }
      if (await store.directory.exists()) {
        await store.directory.rename(
          '${history.path}/orphan-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
      await Directory('${history.path}/$key').rename(store.directory.path);
    } finally {
      _busy = false;
    }
  }

  Future<void> renewCredential(String token) async {
    if (_busy) throw StateError('Ya existe una operación en curso.');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const FormatException('Credencial temporal inválida.');
    }
    final journal = await store.read();
    if (journal == null) throw StateError('No hay intento guardado.');
    await store.write({...journal, 'recovery_token': token});
  }

  Future<Map<String, Object?>> begin({
    required AppMode mode,
    required Directory package,
    required Uri destination,
    required String server,
    required String generation,
    required String token,
    Map<String, Object?>? preparedSource,
    String? connectionRequestId,
  }) async {
    if (mode != AppMode.serverSync) {
      throw StateError('Standalone solo admite diagnóstico.');
    }
    if (_busy) throw StateError('Ya existe una operación en curso.');
    _busy = true;
    try {
      if (await store.read() != null) {
        throw StateError('Reanuda el intento conservado.');
      }
      final reader = RecoveryPackageReader();
      final manifest = await reader.manifest(package);
      final digest = await reader.verify(package, RecoveryCancellation());
      final journal = <String, Object?>{
        'journal_version': 1,
        'prepared_source': ?preparedSource,
        'connection_request_id': ?connectionRequestId,
        'package_path': package.path,
        'package_id': manifest['package_id'],
        'manifest_digest': digest,
        'destination': destination.toString(),
        'server_instance_id': server,
        'generation_id': generation,
        'recovery_token': token,
        'state': 'prepared',
        'recovery_id': null,
        'progress': null,
        'total_chunks': (manifest['chunks'] as List).length,
        'received_chunks': 0,
      };
      await store.write(journal);
      return journal;
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, Object?>> run(
    RecoveryTransport transport, {
    required RecoveryCancellation cancellation,
    void Function(Map<String, Object?>)? onProgress,
    bool publish = false,
    bool abort = false,
  }) async {
    if (_busy) throw StateError('Ya existe una operación en curso.');
    _busy = true;
    try {
      final journal = await store.read();
      if (journal == null) throw StateError('No hay intento guardado.');
      final package = Directory(journal['package_path'] as String),
          reader = RecoveryPackageReader();
      final manifest = await reader.manifest(package);
      await reader.verify(
        package,
        cancellation,
        expectedDigest: journal['manifest_digest'] as String,
      );
      Future<void> save(Map<String, Object?> result) async {
        if (result['recovery_id'] != journal['recovery_id'] &&
            journal['recovery_id'] != null) {
          throw const FormatException('Resultado de otro intento.');
        }
        journal['recovery_id'] = result['recovery_id'];
        journal['state'] = result['state'];
        journal['progress'] = result;
        if (result['state'] == 'completed') {
          journal['received_chunks'] = journal['total_chunks'];
        }
        await store.write(journal);
        onProgress?.call(Map.unmodifiable(journal));
      }

      if (journal['recovery_id'] == null) {
        cancellation.check();
        await save(
          await transport.request(
            'POST',
            '/recovery/sessions',
            bytes: utf8.encode(recoveryCanonical(manifest)),
            headers: {
              'Idempotency-Key': manifest['package_id'] as String,
              'X-Manifest-Sha256': journal['manifest_digest'] as String,
            },
          ),
        );
      }
      final id = journal['recovery_id'] as String;
      Future<Map<String, Object?>> progress([int offset = 0]) async {
        final response = await transport.request(
          'GET',
          '/recovery/sessions/$id?offset=$offset',
        );
        if (response['manifest_digest'] != journal['manifest_digest']) {
          throw const FormatException('Consulta de otro paquete.');
        }
        await save(response);
        return response;
      }

      var current = await progress();
      if (current['state'] == 'completed' || current['state'] == 'aborted') {
        return journal;
      }
      if (abort) {
        cancellation.check();
        await save(
          await transport.request(
            'POST',
            '/recovery/sessions/$id/abort',
            bytes: utf8.encode(
              recoveryCanonical({
                'protocol_version': 1,
                'expected_revision': current['revision'],
                'reason': 'Aborto explícito del operador antes de publicar',
              }),
            ),
          ),
        );
        return journal;
      }
      if (current['state'] == 'receiving') {
        final received = <int>{};
        int? offset = 0;
        while (offset != null) {
          final page = offset == 0 ? current : await progress(offset);
          for (final r in page['received'] as List) {
            final row = r as Map;
            final index = row['chunk_index'] as int;
            final expected = (manifest['chunks'] as List)[index] as Map;
            if (row['digest'] != expected['sha256'] ||
                row['bytes'] != expected['bytes']) {
              throw const FormatException('Lote remoto distinto.');
            }
            received.add(index);
          }
          offset = page['next_offset'] as int?;
        }
        journal['received_chunks'] = received.length;
        await store.write(journal);
        onProgress?.call(Map.unmodifiable(journal));
        var index = 0;
        await for (final bytes in reader.chunks(package, cancellation)) {
          if (!received.contains(index)) {
            cancellation.check();
            final c = (manifest['chunks'] as List)[index] as Map;
            final transferred = await transport.request(
              'PUT',
              '/recovery/sessions/$id/chunks/$index',
              bytes: bytes,
              headers: {
                'Content-Type': 'application/x-ndjson',
                'X-Chunk-Sha256': c['sha256'] as String,
              },
            );
            received.add(index);
            journal['received_chunks'] = received.length;
            await save(transferred);
          }
          index++;
        }
        current = await progress();
      }
      if ([
        'receiving',
        'validating',
        'ready_to_commit',
      ].contains(current['state'])) {
        cancellation.check();
        current = await transport.request(
          'POST',
          '/recovery/sessions/$id/validate',
          bytes: utf8.encode(
            recoveryCanonical({
              'protocol_version': 1,
              'manifest_digest': journal['manifest_digest'],
              'expected_revision': current['revision'],
            }),
          ),
        );
        await save(current);
      }
      if (publish && current['state'] == 'ready_to_commit') {
        cancellation.check();
        await save(
          await transport.request(
            'POST',
            '/recovery/sessions/$id/finalize',
            bytes: utf8.encode(
              recoveryCanonical({
                'protocol_version': 1,
                'validation_digest': current['validation_digest'],
                'expected_revision': current['revision'],
              }),
            ),
          ),
        );
      }
      return journal;
    } finally {
      _busy = false;
    }
  }
}
