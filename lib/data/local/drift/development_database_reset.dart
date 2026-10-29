import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'current_database_schema.dart';

/// Política de desarrollo compartida con el arranque. Solo recibe la ruta
/// explícita; las pruebas usan archivos temporales y nunca la base del usuario.
/// No migra ni cambia schemaVersion. Un respaldo protegido se conserva intacto.
Future<bool> resetDevelopmentDatabase(
  File file, {
  required Future<bool> Function() shouldPreserveRestoredDatabase,
}) async {
  if (!await file.exists()) return false;
  final connection = sqlite.sqlite3.open(file.path);
  final bool current;
  try {
    current = hasCurrentAppDatabaseSchema(connection);
  } finally {
    connection.close();
  }
  if (current) return false;
  if (await shouldPreserveRestoredDatabase()) {
    throw StateError(
      'El respaldo restaurado usa un esquema anterior. Se requiere una base del esquema actual.',
    );
  }
  for (final suffix in ['', '-wal', '-shm']) {
    final old = File('${file.path}$suffix');
    if (await old.exists()) await old.delete();
  }
  return true;
}
