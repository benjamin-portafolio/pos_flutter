import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';
import 'recovery_cancellation.dart';
import 'recovery_diagnostic.dart';
import 'recovery_json.dart';
import 'recovery_snapshot_source.dart';
import 'recovery_snapshot.dart';
import 'recovery_source_binder.dart';
import 'recovery_package_service.dart';
import 'recovery_package_reader.dart';
import 'recovery_attempt_store.dart';
import 'recovery_transfer_service.dart';
import 'recovery_transport.dart';

/// Diagnóstico, preparación y transferencia explícita del corte conservado.
class RecoveryReadinessService {
  RecoveryReadinessService({
    required this.source,
    required this.privateDirectory,
    required this.deviceId,
    required this.appRevision,
    this.openSnapshot,
    this.transportFactory,
    this.sourceBinder,
  });
  final RecoverySnapshotSource source;
  final Future<Directory> Function() privateDirectory;
  final String deviceId;
  final String appRevision;
  final Future<RecoverySnapshot> Function(File)? openSnapshot;
  final RecoveryTransport Function(Map<String, Object?>)? transportFactory;
  final RecoverySourceBinder? sourceBinder;
  Future<void> bindSource(String token) async {
    final binder = sourceBinder,
        package = await prepared(),
        current = await attempt();
    if (binder == null || package == null || current == null) {
      throw StateError('No hay publicación y corte conservados para vincular.');
    }
    await binder.bind(
      prepared: package,
      attempt: current,
      enrollmentToken: token,
    );
  }

  RecoveryTransferService? _transfer;
  Future<RecoveryTransferService> _service() async =>
      _transfer ??= RecoveryTransferService(
        RecoveryAttemptStore(
          Directory('${(await privateDirectory()).path}/attempt'),
        ),
      );

  Future<List<Map<String, Object?>>> history() async {
    final directory = Directory('${(await privateDirectory()).path}/history');
    if (!await directory.exists()) return [];
    final entries = <Map<String, Object?>>[];
    await for (final entry in directory.list(followLinks: false)) {
      final key = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is! Directory ||
          !RegExp(r'^[0-9a-f-]{36}-[0-9]{13,}$').hasMatch(key)) {
        continue;
      }
      try {
        final record = await RecoveryAttemptStore(entry).read();
        if (record != null) {
          entries.add({
            'key': key,
            'package_id': record['package_id'],
            'state': record['state'],
            'destination': record['destination'],
          });
        }
      } on FormatException {
        entries.add({'key': key, 'state': 'invalid_journal'});
      } on FileSystemException {
        entries.add({'key': key, 'state': 'unreadable_journal'});
      }
    }
    entries.sort((a, b) => (b['key'] as String).compareTo(a['key'] as String));
    return entries;
  }

  Future<void> archiveAttempt() async {
    await (await _service()).archive(
      Directory('${(await privateDirectory()).path}/history'),
    );
    final selected = File('${(await privateDirectory()).path}/prepared.json');
    if (await selected.exists()) await selected.delete();
  }

  Future<void> reopenAttempt(String key) async => (await _service()).reopen(
    Directory('${(await privateDirectory()).path}/history'),
    key,
  );
  Future<void> renewCredential(String token) async =>
      (await _service()).renewCredential(token);

  Future<Map<String, Object?>?> attempt() async =>
      (await _service()).store.read();
  Future<Map<String, Object?>> preparePackage(
    Map<String, Object?> report,
    AppMode mode,
    RecoveryCancellation cancellation,
  ) async {
    if (mode != AppMode.serverSync) {
      throw StateError('Standalone solo admite diagnóstico.');
    }
    final opener = openSnapshot;
    if (opener == null) throw StateError('Capturas no configuradas.');
    final snapshot = await opener(File(report['snapshot_path'] as String));
    try {
      final directory = await RecoveryPackageService().generate(
        snapshot,
        privateDirectory: Directory(
          '${(await privateDirectory()).path}/packages',
        ),
        cancellation: cancellation,
      );
      final digest = await RecoveryPackageReader().verify(
        directory,
        cancellation,
      );
      final prepared = <String, Object?>{
        ...report,
        'package_path': directory.path,
        'manifest_digest': digest,
        'package_id': snapshot.cut['package_id'],
      };
      await File(
        '${(await privateDirectory()).path}/prepared.json',
      ).writeAsString(recoveryCanonical(prepared), flush: true);
      return prepared;
    } finally {
      snapshot.close();
    }
  }

  Future<Map<String, Object?>?> prepared() async {
    final current = await attempt();
    if (current?['prepared_source'] is Map) {
      return Map<String, Object?>.from(current!['prepared_source'] as Map);
    }
    final file = File('${(await privateDirectory()).path}/prepared.json');
    if (!await file.exists()) return null;
    return Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<Map<String, Object?>> beginTransfer(
    Map<String, Object?> package,
    Map<String, Object?> target,
    String destination,
    String token,
    AppMode mode,
  ) async {
    if (target['eligible'] != true ||
        target['commercial_recovery_complete'] != true) {
      throw StateError(
        'Destino no habilitado para recuperación comercial completa.',
      );
    }
    final service = await _service();
    final current = await service.begin(
      mode: mode,
      package: Directory(package['package_path'] as String),
      destination: Uri.parse(destination),
      server: target['server_instance_id'] as String,
      generation: target['generation_id'] as String,
      token: token,
    );
    final journal = <String, Object?>{...current, 'prepared_source': package};
    await service.store.write(journal);
    return journal;
  }

  Future<Map<String, Object?>> transfer(
    RecoveryCancellation cancellation, {
    bool publish = false,
    bool abort = false,
    void Function(Map<String, Object?>)? onProgress,
  }) async {
    final factory = transportFactory;
    if (factory == null) throw StateError('Transferencia no configurada.');
    final service = await _service(), journal = await service.store.read();
    if (journal == null) throw StateError('No hay intento guardado.');
    final transport = factory(journal);
    try {
      return await service.run(
        transport,
        cancellation: cancellation,
        publish: publish,
        abort: abort,
        onProgress: onProgress,
      );
    } finally {
      transport.close();
    }
  }

  Future<Map<String, Object?>> diagnose(
    AppMode mode,
    RecoveryCancellation cancellation,
  ) async {
    final snapshot = await source.capture(
      privateDirectory: await privateDirectory(),
      mode: mode,
      deviceId: deviceId,
      appRevision: appRevision,
      cancellation: cancellation,
    );
    try {
      final diagnostic = await RecoveryDiagnostic.inspect(
        snapshot,
        cancellation,
      );
      final report = <String, Object?>{
        'cut': snapshot.cut,
        'diagnostic': diagnostic.toJson(),
        'snapshot_path': snapshot.file.path,
      };
      await File(
        '${snapshot.file.parent.path}/diagnostic.json',
      ).writeAsString(recoveryCanonical(diagnostic.toJson()), flush: true);
      return report;
    } finally {
      snapshot.close();
    }
  }
}
