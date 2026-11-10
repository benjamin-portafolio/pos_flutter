import 'recovery_logical_schema.dart';
import 'recovery_package_reader.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'recovery_cancellation.dart';
import 'recovery_diagnostic.dart';
import 'recovery_json.dart';
import 'recovery_snapshot.dart';

/// Exportación local. S2 recibe exactamente manifest.json y los NDJSON indicados;
/// source.sqlite, cut.json e informe quedan fuera del directorio transferible.
class RecoveryPackageService {
  Future<Directory> generate(
    RecoverySnapshot snapshot, {
    required Directory privateDirectory,
    required RecoveryCancellation cancellation,
    Future<void> Function(File, List<int>)? writeFile,
  }) async {
    cancellation.check();
    await _verifySnapshot(snapshot);
    final diagnostic = await RecoveryDiagnostic.inspect(snapshot, cancellation);
    await File(
      '${snapshot.file.parent.path}/diagnostic.json',
    ).writeAsString(recoveryCanonical(diagnostic.toJson()), flush: true);
    if (!diagnostic.admissible) {
      throw StateError('Origen no admisible; consulte diagnostic.json.');
    }
    await privateDirectory.create(recursive: true);
    final packageId = snapshot.cut['package_id'] as String;
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(packageId)) {
      throw const FormatException('Identidad de paquete inválida.');
    }
    final target = Directory('${privateDirectory.path}/$packageId');
    if (await target.exists()) {
      throw StateError('El paquete publicado ya existe; no se sustituye.');
    }
    final staging = await privateDirectory.createTemp('.recovery-$packageId-');
    final writer =
        writeFile ??
        (File file, List<int> bytes) async {
          await file.writeAsBytes(bytes, flush: true);
        };
    final chunks = <Map<String, Object?>>[];
    var totalBytes = 0;
    try {
      for (final entity in snapshot.exportEntities) {
        var buffer = BytesBuilder(copy: false);
        var rowCount = 0;
        List<String>? previousKey;
        Future<void> flush() async {
          if (rowCount == 0) return;
          cancellation.check();
          if (chunks.length >= 100000) throw StateError('Demasiados lotes.');
          final bytes = buffer.takeBytes();
          totalBytes += bytes.length;
          if (totalBytes > 107374182400) {
            throw StateError('Paquete mayor de 100 GiB.');
          }
          final index = chunks.length;
          final file = '${index.toString().padLeft(6, '0')}-$entity.ndjson';
          final descriptor = <String, Object?>{
            'index': index,
            'entity': entity,
            'file': file,
            'rows': rowCount,
            'bytes': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
          };
          await writer(File('${staging.path}/$file'), bytes);
          // Verifica lo escrito, incluso ante writer con escritura incompleta.
          final actual = File('${staging.path}/$file');
          if (await actual.length() != bytes.length ||
              (await sha256.bind(actual.openRead()).first).toString() !=
                  descriptor['sha256']) {
            throw StateError('Lote escrito incompleto.');
          }
          chunks.add(descriptor);
          rowCount = 0;
          buffer = BytesBuilder(copy: false);
        }

        for (final row in snapshot.exportRows(entity)) {
          cancellation.check();
          final key = RecoveryLogicalSchema.key(entity, row);
          if (previousKey != null &&
              RecoveryLogicalSchema.compare(previousKey, key) >= 0) {
            throw StateError('PK duplicada o desordenada: $entity');
          }
          previousKey = key;
          final bytes = utf8.encode(
            '${recoveryCanonical({'entity': entity, 'row': row})}\n',
          );
          if (bytes.length > 4194304) {
            throw StateError('Fila de $entity mayor de 4 MiB.');
          }
          if (rowCount == 1000 || buffer.length + bytes.length > 4194304) {
            await flush();
          }
          buffer.add(bytes);
          rowCount++;
          await Future<void>.delayed(Duration.zero);
        }
        await flush();
      }
      cancellation.check();
      final manifest = <String, Object?>{
        'format': 'pos-server-recovery/1',
        'package_id': packageId,
        'cut_at': snapshot.cut['cut_at'],
        'source': snapshot.cut['source'],
        'checkpoint': diagnostic.checkpoint,
        'baseline_high_watermark': '${diagnostic.highWatermark}',
        'contracts': <String, Object?>{
          'recovery': 1,
          'bootstrap': 1,
          'sale_adjustments': 1,
          'pricing': [1, 2],
        },
        'eligibility': <String, Object?>{
          'pending': 0,
          'failed': 0,
          'unresolved_incidents': 0,
        },
        'coverage': <String, Object?>{
          'global_completeness': 'unknown',
          'dependency_closure': 'unchecked',
        },
        'exclusions': <Object?>[
          {
            'entity': 'drafts',
            'count': snapshot
                .rows('sales')
                .where((r) => r['status'] != 'confirmada')
                .length,
            'reason': 'local_only',
          },
          {
            'entity': 'quotations',
            'count': snapshot.count('quotations'),
            'reason': 'local_only',
          },
          {
            'entity': 'preferences',
            'count': 0,
            'reason': 'outside_sqlite_not_read',
          },
          {
            'entity': 'local_journals',
            'count': [
              'sale_adjustment_intents',
              'bulk_edit_operations',
              'product_update_undo',
            ].fold(0, (n, t) => n + snapshot.count(t)),
            'reason': 'local_only',
          },
        ],
        'chunks': chunks,
      };
      final bytes = utf8.encode(recoveryCanonical(manifest));
      if (bytes.length > 16777216) {
        throw StateError('Manifest mayor de 16 MiB.');
      }
      await writer(File('${staging.path}/manifest.json'), bytes);
      await RecoveryPackageReader().verify(staging, cancellation);
      await _verifySnapshot(snapshot);
      cancellation.check();
      final digest = sha256.convert(bytes).toString();
      final published = await staging.rename(target.path);
      // Recibo local fuera del paquete, para S5. No modifica el origen.
      await File(
        '${snapshot.file.parent.path}/package-receipt.json',
      ).writeAsString(
        recoveryCanonical({
          'package_id': packageId,
          'manifest_digest': digest,
          'data_revision': snapshot.cut['data_revision'],
          'snapshot_sha256': snapshot.cut['snapshot_sha256'],
          'package_directory': target.path,
        }),
        flush: true,
      );
      return published;
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _verifySnapshot(RecoverySnapshot snapshot) async {
    final actual = (await sha256.bind(snapshot.file.openRead()).first)
        .toString();
    if (actual != snapshot.cut['snapshot_sha256']) {
      throw StateError('La captura fue alterada.');
    }
  }
}
