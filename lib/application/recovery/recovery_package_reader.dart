import 'recovery_logical_schema.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'recovery_cancellation.dart';
import 'recovery_json.dart';

/// Verificación local previa a transferencia; cada yield contiene un único lote
/// de hasta 4 MiB. Los nombres se derivan del índice/entidad, nunca de rutas libres.
class RecoveryPackageReader {
  static final _entity = RegExp(r'^[a-z][a-z_]*$');
  Future<Map<String, Object?>> manifest(Directory directory) async {
    final file = File('${directory.path}/manifest.json');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Manifest no es archivo regular.');
    }
    if (await file.length() > 16777216) {
      throw const FormatException('Manifest demasiado grande.');
    }
    final text = await file.readAsString();
    final m = Map<String, Object?>.from(jsonDecode(text) as Map);
    if (recoveryCanonical(m) != text ||
        m['format'] != 'pos-server-recovery/1' ||
        m['chunks'] is! List ||
        (m['chunks'] as List).length > 100000) {
      throw const FormatException('Manifest incompatible o no canónico.');
    }
    return m;
  }

  Stream<List<int>> chunks(
    Directory directory,
    RecoveryCancellation cancellation,
  ) async* {
    final m = await manifest(directory);
    final allowed = <String>{'manifest.json'};
    var total = 0;
    final previousKeys = <String, List<String>>{};
    for (final (index, raw) in (m['chunks'] as List).indexed) {
      cancellation.check();
      final c = Map<String, Object?>.from(raw as Map);
      final entity = c['entity'];
      if (entity is! String ||
          !_entity.hasMatch(entity) ||
          !RecoveryLogicalSchema.keys.containsKey(entity) ||
          c['index'] != index) {
        throw const FormatException('Descriptor inválido.');
      }
      final name = '${index.toString().padLeft(6, '0')}-$entity.ndjson';
      if (c['file'] != name ||
          c['bytes'] is! int ||
          (c['bytes'] as int) < 1 ||
          (c['bytes'] as int) > 4194304 ||
          c['rows'] is! int ||
          (c['rows'] as int) < 1 ||
          (c['rows'] as int) > 1000) {
        throw const FormatException('Descriptor fuera de límites.');
      }
      allowed.add(name);
      final file = File('${directory.path}/$name');
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != c['bytes']) {
        throw const FormatException('Archivo inválido.');
      }
      final bytes = await file.readAsBytes();
      total += bytes.length;
      if (total > 107374182400 ||
          sha256.convert(bytes).toString() != c['sha256']) {
        throw const FormatException('Checksum incorrecto.');
      }
      final text = utf8.decode(bytes);
      if (!text.endsWith('\n')) throw const FormatException('Falta LF final.');
      final lines = text.substring(0, text.length - 1).split('\n');
      if (lines.length != c['rows'] || lines.toSet().length != lines.length) {
        throw const FormatException('Cantidad/duplicado incorrecto.');
      }
      for (final line in lines) {
        final row = jsonDecode(line) as Map<String, Object?>;
        if (recoveryCanonical(row) != line ||
            row.length != 2 ||
            row['entity'] != entity ||
            row['row'] is! Map ||
            (row['row'] as Map).isEmpty) {
          throw const FormatException('Fila no canónica.');
        }
        final key = RecoveryLogicalSchema.key(
          entity,
          Map<String, Object?>.from(row['row'] as Map),
        );
        final previous = previousKeys[entity];
        if (previous != null &&
            RecoveryLogicalSchema.compare(previous, key) >= 0) {
          throw const FormatException('PK duplicada o desordenada.');
        }
        previousKeys[entity] = key;
      }
      yield bytes;
    }
    await for (final f in directory.list(followLinks: false)) {
      if (!allowed.remove(f.uri.pathSegments.where((s) => s.isNotEmpty).last)) {
        throw const FormatException('Archivo no declarado.');
      }
    }
    if (allowed.isNotEmpty) throw const FormatException('Faltan archivos.');
  }

  Future<String> verify(
    Directory directory,
    RecoveryCancellation cancellation, {
    String? expectedDigest,
  }) async {
    await for (final _ in chunks(directory, cancellation)) {
      /* Solo verifica. */
    }
    final digest =
        (await sha256
                .bind(File('${directory.path}/manifest.json').openRead())
                .first)
            .toString();
    if (expectedDigest != null && digest != expectedDigest) {
      throw const FormatException('Manifest sustituido.');
    }
    return digest;
  }
}
