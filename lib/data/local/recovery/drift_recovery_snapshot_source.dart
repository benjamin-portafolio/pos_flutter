import 'recovery_content_comparer.dart';
import 'sqlite_recovery_snapshot.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../../../application/config/app_config.dart';
import '../../../application/recovery/recovery_cancellation.dart';
import '../../../application/recovery/recovery_json.dart';
import '../../../application/recovery/recovery_snapshot.dart';
import '../../../application/recovery/recovery_snapshot_source.dart';
import '../drift/app_database.dart';
import '../drift/current_database_schema.dart';

/// VACUUM maneja WAL. Exclusión Drift espera writers y aplaza comandos/appliers
/// que comparten este executor; nunca abre una transacción alrededor de VACUUM.
class DriftRecoverySnapshotSource implements RecoverySnapshotSource {
  DriftRecoverySnapshotSource(this.db);
  final AppDatabase db;

  @override
  Future<RecoverySnapshot> capture({
    required Directory privateDirectory,
    required AppMode mode,
    required String deviceId,
    required String appRevision,
    required RecoveryCancellation cancellation,
  }) async {
    cancellation.check();
    if (deviceId.trim().isEmpty ||
        deviceId.length > 120 ||
        appRevision.isEmpty) {
      throw ArgumentError('Identidad de captura inválida.');
    }
    await privateDirectory.create(recursive: true);
    final dir = await privateDirectory.createTemp('capture-');
    final file = File('${dir.path}/source.sqlite');
    Database? copy;
    try {
      final cutAt = await db.exclusively(() async {
        cancellation.check();
        final at = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch,
          isUtc: true,
        ).toIso8601String();
        await db.customStatement('VACUUM INTO ?', [file.path]);
        return at;
      });
      cancellation.check();
      copy = sqlite3.open(file.path, mode: OpenMode.readOnly);
      if (!hasCurrentAppDatabaseSchema(copy) ||
          copy.select('PRAGMA integrity_check').single.values.single != 'ok') {
        throw StateError(
          'Snapshot con esquema desconocido o integridad inválida.',
        );
      }
      final state = copy
          .select('SELECT * FROM recovery_local_state WHERE singleton=1')
          .single;
      final instance = state['server_instance_id'];
      final generation = state['generation_id'];
      if ((instance == null) != (generation == null)) {
        throw StateError('Identidad incompleta.');
      }
      final ddl = copy
          .select(
            "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type,name",
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      final cut = <String, Object?>{
        'package_id': const Uuid().v4(),
        'cut_at': cutAt,
        'data_revision': state['data_revision'].toString(),
        'source_dataset_id': state['dataset_id'],
        'snapshot_sha256': (await sha256.bind(file.openRead()).first)
            .toString(),
        'source': <String, Object?>{
          'mode': mode.storageValue,
          'device_id': deviceId,
          'app_revision': appRevision,
          'schema_version': 10,
          'schema_fingerprint': sha256
              .convert(utf8.encode(recoveryCanonical(ddl)))
              .toString(),
          'server_instance_id': instance,
          'generation_id': generation,
          'identity_provenance': instance == null ? 'legacy_unknown' : 'known',
        },
      };
      cancellation.check();
      await File(
        '${dir.path}/cut.json',
      ).writeAsString(recoveryCanonical(cut), flush: true);
      final snapshot = SqliteRecoverySnapshot(file, cut, copy);
      copy = null;
      return snapshot;
    } catch (_) {
      copy?.close();
      // Solo la captura nueva es nuestra. No se toca origen ni otro paquete.
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<bool> hasChangesSince(
    RecoverySnapshot snapshot,
  ) => db.exclusively(() async {
    final now = await db
        .customSelect('SELECT * FROM recovery_local_state WHERE singleton=1')
        .getSingle();
    final source = snapshot.cut['source'] as Map;
    if (now.data['data_revision'].toString() != snapshot.cut['data_revision'] ||
        now.data['server_instance_id'] != source['server_instance_id'] ||
        now.data['generation_id'] != source['generation_id'] ||
        now.data['dataset_id'] != snapshot.cut['source_dataset_id']) {
      return true;
    }
    // Un restore puede reinstalar un contador antiguo y volver a alcanzar el
    // mismo número. La igualdad del contador no basta para autorizar sustitución.
    // Una segunda captura canónica detecta ese caso, sin tocar la preservada.
    final compare = await Directory.systemTemp.createTemp(
      'pos-recovery-compare-',
    );
    try {
      final file = File('${compare.path}/current.sqlite');
      await db.customStatement('VACUUM INTO ?', [file.path]);
      return !RecoveryContentComparer.matches(snapshot.file, file);
    } finally {
      await compare.delete(recursive: true);
    }
  });
}
