import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../application/backup/backup_manifest.dart';
import '../../application/backup/backup_store.dart';
import 'google_drive_auth_service.dart';

class GoogleDriveBackupStore implements BackupStore {
  GoogleDriveBackupStore({
    required GoogleDriveAuthService authService,
    http.Client? client,
  }) : _authService = authService,
       _client = client ?? http.Client();

  final GoogleDriveAuthService _authService;
  final http.Client _client;

  @override
  Future<BackupStoreSession?> openSession({required bool interactive}) async {
    final authSession = await _authService.authorize(interactive: interactive);
    if (authSession == null) return null;

    return _GoogleDriveBackupStoreSession(
      client: _client,
      authSession: authSession,
    );
  }
}

class _GoogleDriveBackupStoreSession implements BackupStoreSession {
  _GoogleDriveBackupStoreSession({
    required http.Client client,
    required GoogleDriveAuthSession authSession,
  }) : _client = client,
       _authSession = authSession;

  final http.Client _client;
  final GoogleDriveAuthSession _authSession;

  @override
  BackupAccount get account => _authSession.account;

  @override
  Future<BackupManifest?> readLatestManifest() async {
    final fileId = await _findFileId(BackupManifest.manifestFileName);
    if (fileId == null) return null;

    final bytes = await _downloadFileBytes(fileId);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, Object?>) {
      return BackupManifest.fromJson(decoded);
    }
    if (decoded is Map) {
      return BackupManifest.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    throw const BackupStoreException('Manifest de respaldo invalido.');
  }

  @override
  Future<void> uploadBackup({
    required File databaseFile,
    required BackupManifest manifest,
  }) async {
    await _uploadFile(
      name: BackupManifest.latestDatabaseFileName,
      bytes: await databaseFile.readAsBytes(),
      contentType: 'application/x-sqlite3',
    );
    await _uploadFile(
      name: BackupManifest.manifestFileName,
      bytes: utf8.encode(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      ),
      contentType: 'application/json; charset=UTF-8',
    );
  }

  @override
  Future<File?> downloadLatestDatabase({required Directory destination}) async {
    final fileId = await _findFileId(BackupManifest.latestDatabaseFileName);
    if (fileId == null) return null;

    await destination.create(recursive: true);
    final file = File(
      p.join(destination.path, BackupManifest.latestDatabaseFileName),
    );
    await file.writeAsBytes(await _downloadFileBytes(fileId), flush: true);
    return file;
  }

  Future<String?> _findFileId(String name) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "name = '${_escapeDriveQueryValue(name)}' and trashed = false",
      'fields': 'files(id,name)',
      'pageSize': '1',
    });
    final response = await _client.get(uri, headers: _authHeaders());
    _ensureSuccess(response, 'No se pudo buscar respaldo en Google Drive.');

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;

    final files = decoded['files'];
    if (files is! List || files.isEmpty) return null;

    final first = files.first;
    if (first is Map) return first['id'] as String?;
    return null;
  }

  Future<Uint8List> _downloadFileBytes(String fileId) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
      'alt': 'media',
    });
    final response = await _client.get(uri, headers: _authHeaders());
    _ensureSuccess(response, 'No se pudo descargar respaldo de Google Drive.');
    return response.bodyBytes;
  }

  Future<void> _uploadFile({
    required String name,
    required List<int> bytes,
    required String contentType,
  }) async {
    final existingFileId = await _findFileId(name);
    final isUpdate = existingFileId != null;
    final uri = Uri.https(
      'www.googleapis.com',
      isUpdate
          ? '/upload/drive/v3/files/$existingFileId'
          : '/upload/drive/v3/files',
      {'uploadType': 'multipart', 'fields': 'id'},
    );
    final request = http.Request(isUpdate ? 'PATCH' : 'POST', uri);
    final boundary = 'pos_backup_${DateTime.now().microsecondsSinceEpoch}';
    request.headers.addAll(_authHeaders());
    request.headers['Content-Type'] = 'multipart/related; boundary=$boundary';
    request.bodyBytes = _multipartRelatedBody(
      boundary: boundary,
      metadata: {
        'name': name,
        if (!isUpdate) 'parents': ['appDataFolder'],
      },
      bytes: bytes,
      contentType: contentType,
    );

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _ensureSuccess(response, 'No se pudo subir respaldo a Google Drive.');
  }

  Map<String, String> _authHeaders() {
    return Map<String, String>.of(_authSession.authHeaders);
  }
}

Uint8List _multipartRelatedBody({
  required String boundary,
  required Map<String, Object?> metadata,
  required List<int> bytes,
  required String contentType,
}) {
  final builder = BytesBuilder();

  void addText(String value) {
    builder.add(utf8.encode(value));
  }

  addText('--$boundary\r\n');
  addText('Content-Type: application/json; charset=UTF-8\r\n\r\n');
  addText(jsonEncode(metadata));
  addText('\r\n--$boundary\r\n');
  addText('Content-Type: $contentType\r\n\r\n');
  builder.add(bytes);
  addText('\r\n--$boundary--\r\n');

  return builder.takeBytes();
}

String _escapeDriveQueryValue(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}

void _ensureSuccess(http.Response response, String message) {
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  throw BackupStoreException('$message (${response.statusCode})');
}
