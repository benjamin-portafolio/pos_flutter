import 'dart:convert';
import 'dart:io';
import '../../../application/recovery/recovery_json.dart';

class SyncInstallationFileStore {
  SyncInstallationFileStore(this.directory);
  final Directory directory;
  File get file => File('${directory.path}/installation.json');
  Future<Map<String, Object?>?> read() async {
    if (!await file.exists()) return null;
    final text = await file.readAsString(),
        value = Map<String, Object?>.from(jsonDecode(text) as Map);
    if (recoveryCanonical(value) != text) {
      throw const FormatException('Instalación no canónica.');
    }
    validate(value);
    return value;
  }

  static void validate(Map<String, Object?> value) {
    if (value['installation_version'] != 1 ||
        !['active', 'needs_pull'].contains(value['phase'])) {
      throw const FormatException(
        'Instalación de sincronización incompatible.',
      );
    }
    final binding = value['binding'] as Map;
    for (final key in [
      'device_id',
      'server_instance_id',
      'generation_id',
      'dataset_id',
    ]) {
      if (binding[key] is! String ||
          !RegExp(r'^[0-9a-f-]{36}$').hasMatch(binding[key] as String)) {
        throw const FormatException('Identidad de sincronización incompleta.');
      }
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(binding['token'] as String)) {
      throw const FormatException('Binding inválido.');
    }
  }

  Future<void> write(Map<String, Object?> value) async {
    validate(value);
    await directory.create(recursive: true);
    final temporary = await directory.createTemp('.installation-');
    try {
      final staged = File('${temporary.path}/value');
      await staged.writeAsString(recoveryCanonical(value), flush: true);
      await staged.rename(file.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}
