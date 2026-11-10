import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../../application/recovery/recovery_json.dart';

/// Private immutable chunks, addressed by the full verified descriptor digest.
/// Failed transfers keep only checksum-verified bytes for the next attempt.
class BootstrapDownloadCache {
  BootstrapDownloadCache(Directory root, Map<String, Object?> descriptor)
    : directory = Directory(
        '${root.path}/download-${sha256.convert(utf8.encode(recoveryCanonical(descriptor)))}',
      );
  final Directory directory;

  Future<List<int>> chunk(
    Map<String, Object?> descriptor,
    Future<List<int>> Function(int) download,
  ) async {
    await directory.create(recursive: true);
    final index = descriptor['index'] as int;
    final file = File('${directory.path}/$index.ndjson');
    bool valid(List<int> bytes) =>
        bytes.length == descriptor['bytes'] &&
        sha256.convert(bytes).toString() == descriptor['sha256'];
    if (await file.exists()) {
      if (await file.length() == descriptor['bytes']) {
        final bytes = await file.readAsBytes();
        if (valid(bytes)) return bytes;
      }
      await file.delete();
    }
    final bytes = await download(index);
    if (!valid(bytes)) {
      throw const FormatException('Integridad bootstrap inválida.');
    }
    // A crash during the temporary write cannot expose an incomplete chunk.
    final temporary = await directory.createTemp('chunk-');
    try {
      await File('${temporary.path}/bytes').writeAsBytes(bytes, flush: true);
      await File('${temporary.path}/bytes').rename(file.path);
    } finally {
      await temporary.delete(recursive: true);
    }
    return bytes;
  }
}
