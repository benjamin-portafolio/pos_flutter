import 'dart:convert';
import 'dart:io';
import 'recovery_json.dart';

/// One private journal per package. Tokens are scoped recovery credentials.
class RecoveryAttemptStore {
  RecoveryAttemptStore(this.directory);
  final Directory directory;
  File get file => File('${directory.path}/attempt.json');
  Future<T> withFileLock<T>(Future<T> Function() action) async {
    await directory.create(recursive: true);
    final lock = await File(
      '${directory.path}/.lock',
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      return await action();
    } finally {
      await lock.close();
    }
  }

  Future<Map<String, Object?>?> read() async {
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Diario de recuperación incompatible.');
    }
    final value = Map<String, Object?>.from(decoded);
    if (recoveryCanonical(value) != text || value['journal_version'] != 1) {
      throw const FormatException('Diario de recuperación incompatible.');
    }
    return value;
  }

  Future<void> write(Map<String, Object?> value) async {
    await directory.create(recursive: true);
    final temporary = await directory.createTemp('.journal-');
    try {
      final staged = File('${temporary.path}/attempt.json');
      await staged.writeAsString(
        recoveryCanonical({...value, 'journal_version': 1}),
        flush: true,
      );
      await staged.rename(file.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}
