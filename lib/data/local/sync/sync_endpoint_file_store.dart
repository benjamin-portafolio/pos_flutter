import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../application/sync/sync_endpoint_store.dart';

typedef SyncEndpointDirectoryProvider = Future<Directory> Function();

class SyncEndpointFileStore implements SyncEndpointStore {
  SyncEndpointFileStore({SyncEndpointDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'sync_endpoint.txt';

  final SyncEndpointDirectoryProvider _directoryProvider;

  @override
  Future<String?> readBaseUrl() async {
    final file = await _endpointFile();
    if (!await file.exists()) return null;

    final value = (await file.readAsString()).trim();
    if (value.isEmpty) return null;
    return value;
  }

  @override
  Future<void> saveBaseUrl(String baseUrl) async {
    final file = await _endpointFile();
    await file.writeAsString('${baseUrl.trim()}\n', flush: true);
  }

  Future<File> _endpointFile() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    return File(p.join(directory.path, _fileName));
  }
}
