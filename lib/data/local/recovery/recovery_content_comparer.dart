import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import '../../../application/recovery/recovery_json.dart';
import '../drift/recovery_revision_schema.dart';
import '../drift/current_database_schema.dart';

/// Compare every persisted value and sequence, not SQLite page headers changed
/// by reopening/VACUUM. Cursors retain one row per side, including excluded data.
class RecoveryContentComparer {
  static bool matches(File original, File current) {
    final left = sqlite3.open(original.path, mode: OpenMode.readOnly),
        right = sqlite3.open(current.path, mode: OpenMode.readOnly);
    try {
      if (!hasCurrentAppDatabaseSchema(left) ||
          !hasCurrentAppDatabaseSchema(right)) {
        return false;
      }
      for (final table in [
        ...recoveryRevisionTables,
        'recovery_local_state',
        'sqlite_sequence',
      ]) {
        final columns = left.select('PRAGMA table_info("$table")');
        final primary = columns.where((c) => (c['pk'] as int) > 0).toList()
          ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
        final order = primary.isEmpty
            ? columns.map((c) => '"${c['name']}"').join(',')
            : primary.map((c) => '"${c['name']}"').join(',');
        final a = left.prepare('SELECT * FROM "$table" ORDER BY $order'),
            b = right.prepare('SELECT * FROM "$table" ORDER BY $order');
        try {
          final ac = a.selectCursor(), bc = b.selectCursor();
          while (true) {
            final moreA = ac.moveNext(), moreB = bc.moveNext();
            if (moreA != moreB) return false;
            if (!moreA) break;
            if (recoveryCanonical(Map<String, Object?>.from(ac.current)) !=
                recoveryCanonical(Map<String, Object?>.from(bc.current))) {
              return false;
            }
          }
        } finally {
          a.close();
          b.close();
        }
      }
      return true;
    } finally {
      left.close();
      right.close();
    }
  }
}
