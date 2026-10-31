import 'dart:convert';
import 'dart:io';

File _journal(File target) => File('${target.path}.restore-journal');

/// Una sustitución interrumpida se revierte antes de abrir SQLite.
Future<void> recoverDatabaseReplacement(File target) async {
  final journal = _journal(target);
  if (!await journal.exists()) return;
  final data = jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
  final backup = Directory(data['backup'] as String);
  for (final suffix in ['', '-wal', '-shm']) {
    final previous = File('${backup.path}/database$suffix');
    final destination = File('${target.path}$suffix');
    if (await previous.exists()) {
      if (await destination.exists()) await destination.delete();
      await previous.rename(destination.path);
    } else if (!(data['original'] as List).contains(suffix) &&
        await destination.exists()) {
      await destination.delete();
    }
  }
  await journal.delete();
}

/// Conexiones cerradas. Staging y copia anterior en el mismo filesystem.
/// El diario durable permite recuperar tras error o interrupción del proceso.
Future<void> replaceDatabaseSafely(
  File target,
  File staged, {
  required Future<void> Function() markRestored,
  Future<void> Function()? afterBackupForTesting,
}) async {
  await recoverDatabaseReplacement(target);
  final backup = await target.parent.createTemp('pos-before-restore-');
  final original = <String>[];
  for (final suffix in ['', '-wal', '-shm']) {
    if (await File('${target.path}$suffix').exists()) original.add(suffix);
  }
  final journal = _journal(target);
  await journal.writeAsString(
    jsonEncode({'backup': backup.path, 'original': original}),
    flush: true,
  );
  try {
    for (final suffix in original) {
      await File(
        '${target.path}$suffix',
      ).rename('${backup.path}/database$suffix');
    }
    await afterBackupForTesting?.call();
    await staged.rename(target.path);
    await markRestored();
    await journal.delete();
    // Se conserva la última base válida para recuperación manual adicional.
  } catch (_) {
    await recoverDatabaseReplacement(target);
    rethrow;
  }
}
