import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../../../application/sync/sync_capability_store.dart';

/// Installation metadata, deliberately outside the business backup. A restored
/// database on another installation must first negotiate its own server.
class SyncCapabilityFileStore implements SyncCapabilityStore {
  SyncCapabilityFileStore({Future<Directory> Function()? directoryProvider})
    : _directory = directoryProvider ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<File> _file(String endpoint) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final key = sha256.convert(utf8.encode(endpoint));
    return File('${directory.path}/sync-capabilities-$key.json');
  }

  @override
  Future<List<String>?> read(String endpoint) async {
    final file = await _file(endpoint);
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! List || value.any((v) => v is! String)) return null;
      return value.cast<String>();
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String endpoint, List<String> capabilities) async {
    final file = await _file(endpoint);
    final directory = await file.parent.createTemp('capability-write-');
    try {
      final temporary = File('${directory.path}/value.json');
      await temporary.writeAsString(jsonEncode(capabilities), flush: true);
      await temporary.rename(file.path);
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
